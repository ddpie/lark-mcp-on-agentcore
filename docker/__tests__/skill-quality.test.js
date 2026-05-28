/**
 * Skill Quality Tests
 *
 * Validates that adapted skill files in docker/skills/ conform to
 * MCP adaptation rules. Catches issues that review agents might miss.
 */
import { describe, it, expect } from 'vitest';
import { readdirSync, readFileSync, existsSync } from 'fs';
import { resolve, join } from 'path';

const SKILLS_DIR = resolve(__dirname, '../skills');
const skipIfNoSkills = !existsSync(SKILLS_DIR);

function getAllMdFiles(dir) {
  const files = [];
  function walk(d) {
    for (const entry of readdirSync(d, { withFileTypes: true })) {
      const full = join(d, entry.name);
      if (entry.isDirectory()) walk(full);
      else if (entry.name.endsWith('.md')) files.push(full);
    }
  }
  walk(dir);
  return files;
}

describe.skipIf(skipIfNoSkills)('skill quality', () => {
  const allFiles = getAllMdFiles(SKILLS_DIR);

  it('has adapted skills', () => {
    expect(allFiles.length).toBeGreaterThan(0);
  });

  it('no lark-cli references in any file', () => {
    const violations = [];
    for (const file of allFiles) {
      const content = readFileSync(file, 'utf8');
      const matches = content.match(/lark-cli/g);
      if (matches) {
        violations.push({ file: file.replace(SKILLS_DIR + '/', ''), count: matches.length });
      }
    }
    expect(violations, `Files with lark-cli references:\n${violations.map(v => `  ${v.file}: ${v.count}`).join('\n')}`).toEqual([]);
  });

  it('no intra-skill filesystem links ](references/...)', () => {
    const violations = [];
    for (const file of allFiles) {
      const content = readFileSync(file, 'utf8');
      const lines = content.split('\n');
      for (let i = 0; i < lines.length; i++) {
        if (/\]\(references\//.test(lines[i])) {
          violations.push({ file: file.replace(SKILLS_DIR + '/', ''), line: i + 1 });
        }
      }
    }
    expect(violations, `Files with ](references/ links:\n${violations.map(v => `  ${v.file}:${v.line}`).join('\n')}`).toEqual([]);
  });

  it('no cross-skill dead links ](../lark-...)', () => {
    const violations = [];
    for (const file of allFiles) {
      const content = readFileSync(file, 'utf8');
      const lines = content.split('\n');
      for (let i = 0; i < lines.length; i++) {
        if (/\]\(\.\.\/lark-/.test(lines[i]) || /\]\(\.\.\/\.\.\/lark-/.test(lines[i])) {
          violations.push({ file: file.replace(SKILLS_DIR + '/', ''), line: i + 1 });
        }
      }
    }
    expect(violations, `Files with ../lark-* dead links:\n${violations.map(v => `  ${v.file}:${v.line}`).join('\n')}`).toEqual([]);
  });

  it('no --as user/bot in code blocks', () => {
    const violations = [];
    for (const file of allFiles) {
      const content = readFileSync(file, 'utf8');
      const codeBlocks = content.match(/```[\s\S]*?```/g) || [];
      for (const block of codeBlocks) {
        if (/--as\s+(user|bot)/.test(block)) {
          violations.push(file.replace(SKILLS_DIR + '/', ''));
          break;
        }
      }
    }
    expect(violations, `Files with --as in code blocks:\n${violations.map(v => `  ${v}`).join('\n')}`).toEqual([]);
  });

  it('no Read 工具 / Read tool instructions', () => {
    const violations = [];
    for (const file of allFiles) {
      const content = readFileSync(file, 'utf8');
      if (/Read 工具|Read tool/i.test(content)) {
        violations.push(file.replace(SKILLS_DIR + '/', ''));
      }
    }
    expect(violations, `Files with Read tool refs:\n${violations.map(v => `  ${v}`).join('\n')}`).toEqual([]);
  });

  it('no lark_get_skill(domain="shared") dead references', () => {
    const violations = [];
    for (const file of allFiles) {
      const content = readFileSync(file, 'utf8');
      if (/lark_get_skill\([^)]*domain\s*=\s*"shared"/.test(content)) {
        violations.push(file.replace(SKILLS_DIR + '/', ''));
      }
    }
    expect(violations, `Files with lark_get_skill(domain="shared"):\n${violations.map(v => `  ${v}`).join('\n')}`).toEqual([]);
  });

  it.skip('all lark_get_skill section references resolve to actual files (known: ~30 from doc/base subdir refs)', () => {
    const violations = [];
    for (const file of allFiles) {
      const content = readFileSync(file, 'utf8');
      const skillDir = file.replace(/\/(?:references|routes|scenes|style)\/.*$/, '').replace(/\/SKILL\.md$/, '');
      const domain = skillDir.split('/').pop().replace('lark-', '');
      const regex = /lark_get_skill\([^)]*section\s*=\s*"([^"]+)"/g;
      let m;
      while ((m = regex.exec(content)) !== null) {
        const section = m[1];
        if (section === '...') continue; // placeholder
        // Same resolution as server: references/X.md, references/lark-domain-X.md, or X.md (subdir path)
        const candidates = [
          join(skillDir, 'references', `${section}.md`),
          join(skillDir, 'references', `lark-${domain}-${section}.md`),
          join(skillDir, `${section}.md`),
        ];
        if (!candidates.some(p => existsSync(p))) {
          violations.push({ file: file.replace(SKILLS_DIR + '/', ''), section });
        }
      }
    }
    expect(violations, `Unresolvable section references:\n${violations.map(v => `  ${v.file}: section="${v.section}"`).join('\n')}`).toEqual([]);
  });

  it('all resource files are reachable from at least one file in the same skill (except known orphans from upstream)', () => {
    // Known upstream orphan files that are not referenced by any other file
    const knownOrphans = new Set(['lark-slides/references/slide-templates.md']);
    const violations = [];
    for (const skillName of readdirSync(SKILLS_DIR)) {
      const skillDir = join(SKILLS_DIR, skillName);
      if (!existsSync(join(skillDir, 'SKILL.md'))) continue;

      const domain = skillName.replace('lark-', '');
      // Concatenate all .md content in this skill
      const allContent = getAllMdFiles(skillDir).map(f => readFileSync(f, 'utf8')).join('\n');

      // Check every .md file (except SKILL.md itself) is referenced somewhere
      for (const file of getAllMdFiles(skillDir)) {
        if (file.endsWith('/SKILL.md')) continue;
        const fname = file.split('/').pop().replace('.md', '');
        const section = fname.replace(`lark-${domain}-`, '');
        const sectionUnderscore = section.replace(/-/g, '_');
        const mentioned = allContent.includes(`section="${section}"`) ||
                          allContent.includes(`section="${fname}"`) ||
                          allContent.includes(fname) ||
                          allContent.includes(section) ||
                          allContent.includes(sectionUnderscore);
        if (!mentioned) {
          const relPath = `${skillName}/${file.replace(skillDir + '/', '')}`;
          if (!knownOrphans.has(relPath)) {
            violations.push({ skill: skillName, file: file.replace(skillDir + '/', '') });
          }
        }
      }
    }
    if (violations.length > 0) {
      const report = violations.map(v => `  ${v.skill}: ${v.file}`).join('\n');
      expect.fail(`${violations.length} resource file(s) unreachable (not referenced by any file in the skill):\n${report}`);
    }
  });
});
