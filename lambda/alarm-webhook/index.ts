import i18n from '../../config/i18n.json';

interface SNSRecord { Sns: { Message: string; Subject?: string; Timestamp?: string } }
interface SNSEvent { Records: SNSRecord[] }

const WEBHOOK_URL = process.env.FEISHU_WEBHOOK_URL || '';
const LANG = process.env.DEPLOY_LANG || 'en';
const t = i18n.alarm[LANG as keyof typeof i18n.alarm] || i18n.alarm.en;

interface AlarmMessage {
  AlarmName?: string;
  NewStateValue?: string;
  NewStateReason?: string;
  StateChangeTime?: string;
  Region?: string;
  OldStateValue?: string;
}

export async function handler(event: SNSEvent): Promise<void> {
  if (!WEBHOOK_URL) return;
  for (const record of event.Records) {
    let alarm: AlarmMessage;
    try {
      alarm = JSON.parse(record.Sns.Message);
    } catch {
      alarm = { AlarmName: 'Unknown', NewStateReason: record.Sns.Message };
    }

    const isAlarm = alarm.NewStateValue === 'ALARM';
    const title = isAlarm
      ? `🔴 ${t.alarm}: ${alarm.AlarmName}`
      : `✅ ${t.ok}: ${alarm.AlarmName}`;

    const card = {
      msg_type: 'interactive',
      card: {
        header: {
          title: { tag: 'plain_text', content: title },
          template: isAlarm ? 'red' : 'green',
        },
        elements: [
          {
            tag: 'div',
            fields: [
              { is_short: true, text: { tag: 'lark_md', content: `**${t.status}:** ${alarm.NewStateValue || 'N/A'}` } },
              { is_short: true, text: { tag: 'lark_md', content: `**${t.region}:** ${alarm.Region || process.env.AWS_REGION || 'N/A'}` } },
            ],
          },
          {
            tag: 'div',
            text: { tag: 'lark_md', content: `**${t.reason}:**\n${alarm.NewStateReason || 'N/A'}` },
          },
          {
            tag: 'div',
            fields: [
              { is_short: true, text: { tag: 'lark_md', content: `**${t.time}:** ${alarm.StateChangeTime || new Date().toISOString()}` } },
              { is_short: true, text: { tag: 'lark_md', content: `**${t.previous}:** ${alarm.OldStateValue || 'N/A'}` } },
            ],
          },
        ],
      },
    };

    const resp = await fetch(WEBHOOK_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(card),
    });
    if (!resp.ok) {
      console.log(JSON.stringify({ level: 'ERROR', event: 'webhook_send_failed', status: resp.status, body: await resp.text() }));
    }
  }
}
