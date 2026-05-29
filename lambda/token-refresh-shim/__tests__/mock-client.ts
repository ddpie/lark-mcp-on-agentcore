/**
 * Lightweight mocks for the AWS SDK clients the token-refresh-shim uses.
 * Captures Send calls and lets each test seed/fail specific operations.
 */

interface SecretStore { [id: string]: string }
let store: SecretStore = {};
let listNames: string[] = [];
let failOpName: string | null = null;
let failOpError: { name: string; message: string } | null = null;
let putCount = 0;
let failOnPutFrom = -1;
// Failure trigger that depends on the SecretId (e.g. fail GET on a specific secret only)
let failGetMatch: { idMatch: string; err: { name: string; message: string } } | null = null;
let failCreateMatch: { nameMatch: string; err: { name: string; message: string } } | null = null;
// Failure trigger for PUT that matches SecretId
let failPutMatch: { idMatch: string; err: { name: string; message: string } } | null = null;

// DDB code store (for /token grant exchange)
interface CodeRow { code: string; userId: string; codeChallenge: string; redirectUri: string; expiresAt: number }
let codeStore: Map<string, CodeRow> = new Map();

// DDB openid-map store
let openidStore: Map<string, string> = new Map();

// SSM store
let ssmStore: { [name: string]: string } = { '/lark-mcp-on-agentcore/state-secret': 'test-state-secret-value' };

// Openid DDB failure triggers
let failOpenidGet: { name: string; message: string } | null = null;
let failOpenidPut: { name: string; message: string } | null = null;

const reset = () => {
  store = {};
  listNames = [];
  failOpName = null;
  failOpError = null;
  putCount = 0;
  failOnPutFrom = -1;
  failGetMatch = null;
  failCreateMatch = null;
  failPutMatch = null;
  codeStore = new Map();
  openidStore = new Map();
  failOpenidGet = null;
  failOpenidPut = null;
  ssmStore = { '/lark-mcp-on-agentcore/state-secret': 'test-state-secret-value' };
};

class GetSecretValueCommand { constructor(public input: any) {} }
class PutSecretValueCommand { constructor(public input: any) {} }
class CreateSecretCommand { constructor(public input: any) {} }
class ListSecretsCommand { constructor(public input: any) {} }

class SecretsManagerClient {
  send(cmd: any): Promise<any> {
    const cmdName = cmd.constructor.name;

    if (failOpName === cmdName && failOpError) {
      const err: any = new Error(failOpError.message);
      err.name = failOpError.name;
      return Promise.reject(err);
    }

    if (cmd instanceof PutSecretValueCommand) {
      putCount++;
      if (failPutMatch && cmd.input.SecretId.includes(failPutMatch.idMatch)) {
        const err: any = new Error(failPutMatch.err.message);
        err.name = failPutMatch.err.name;
        return Promise.reject(err);
      }
      if (failOnPutFrom > 0 && putCount >= failOnPutFrom && failOpError) {
        const err: any = new Error(failOpError.message);
        err.name = failOpError.name;
        return Promise.reject(err);
      }
      store[cmd.input.SecretId] = cmd.input.SecretString;
      return Promise.resolve({ ARN: 'arn', VersionId: 'v' });
    }

    if (cmd instanceof CreateSecretCommand) {
      if (failCreateMatch && cmd.input.Name.includes(failCreateMatch.nameMatch)) {
        const err: any = new Error(failCreateMatch.err.message);
        err.name = failCreateMatch.err.name;
        return Promise.reject(err);
      }
      store[cmd.input.Name] = cmd.input.SecretString;
      return Promise.resolve({ ARN: 'arn' });
    }

    if (cmd instanceof GetSecretValueCommand) {
      if (failGetMatch && cmd.input.SecretId.includes(failGetMatch.idMatch)) {
        const err: any = new Error(failGetMatch.err.message);
        err.name = failGetMatch.err.name;
        return Promise.reject(err);
      }
      const v = store[cmd.input.SecretId];
      if (!v) {
        const err: any = new Error('not found');
        err.name = 'ResourceNotFoundException';
        return Promise.reject(err);
      }
      return Promise.resolve({ SecretString: v });
    }

    if (cmd instanceof ListSecretsCommand) {
      return Promise.resolve({ SecretList: listNames.map(n => ({ Name: n })) });
    }

    return Promise.reject(new Error(`Unmocked command: ${cmdName}`));
  }
}

class GetParameterCommand { constructor(public input: any) {} }

class SSMClient {
  send(cmd: any): Promise<any> {
    if (cmd instanceof GetParameterCommand) {
      const v = ssmStore[cmd.input.Name];
      if (!v) return Promise.reject(Object.assign(new Error('not found'), { name: 'ParameterNotFound' }));
      return Promise.resolve({ Parameter: { Value: v } });
    }
    return Promise.reject(new Error(`Unmocked SSM command`));
  }
}

// Test helpers attached to the module export so tests can drive the mock.
export const mockClient = {
  reset,
  ssm: {
    SSMClient,
    GetParameterCommand,
    __set: (name: string, value: string) => { ssmStore[name] = value; },
  },
  secretsManager: {
    SecretsManagerClient,
    GetSecretValueCommand,
    PutSecretValueCommand,
    CreateSecretCommand,
    ListSecretsCommand,
    __set: (id: string, value: string) => { store[id] = value; },
    __get: (id: string) => store[id],
    __listNames: (names: string[]) => { listNames = names; },
    __failOn: (op: string, err: { name: string; message: string }) => { failOpName = op; failOpError = err; },
    __failOnPutFrom: (n: number, err: { name: string; message: string }) => { failOnPutFrom = n; failOpError = err; },
    __failGetMatching: (idMatch: string, err: { name: string; message: string }) => { failGetMatch = { idMatch, err }; },
    __failCreateMatching: (nameMatch: string, err: { name: string; message: string }) => { failCreateMatch = { nameMatch, err }; },
    __failPutMatching: (idMatch: string, err: { name: string; message: string }) => { failPutMatch = { idMatch, err }; },
  },
  dynamodb: {
    DynamoDBDocumentClient: {
      from: () => ({
        send: (cmd: any) => {
          const cmdName = cmd.constructor.name;
          const table = cmd.input?.TableName || '';
          if (cmdName === 'PutCommand') {
            if (table.includes('openid-map')) {
              if (failOpenidPut) {
                const err: any = new Error(failOpenidPut.message);
                err.name = failOpenidPut.name;
                return Promise.reject(err);
              }
              openidStore.set(cmd.input.Item.openId, cmd.input.Item.userId);
              return Promise.resolve({});
            }
            const it = cmd.input.Item;
            codeStore.set(it.code, { code: it.code, userId: it.userId, codeChallenge: it.codeChallenge, redirectUri: it.redirectUri, expiresAt: it.expiresAt });
            return Promise.resolve({});
          }
          if (cmdName === 'GetCommand') {
            if (failOpenidGet) {
              const err: any = new Error(failOpenidGet.message);
              err.name = failOpenidGet.name;
              return Promise.reject(err);
            }
            const userId = openidStore.get(cmd.input.Key.openId);
            return Promise.resolve(userId ? { Item: { openId: cmd.input.Key.openId, userId } } : {});
          }
          if (cmdName === 'DeleteCommand') {
            const row = codeStore.get(cmd.input.Key.code);
            codeStore.delete(cmd.input.Key.code);
            return Promise.resolve(row ? { Attributes: row } : {});
          }
          return Promise.resolve({});
        },
      }),
    },
    PutCommand: class { constructor(public input: any) {} },
    GetCommand: class { constructor(public input: any) {} },
    DeleteCommand: class { constructor(public input: any) {} },
    __seedCode: (row: CodeRow) => { codeStore.set(row.code, row); },
    __hasCode: (code: string) => codeStore.has(code),
    __setOpenId: (openId: string, userId: string) => { openidStore.set(openId, userId); },
    __getOpenId: (openId: string) => openidStore.get(openId),
    __failOpenidGet: (err: { name: string; message: string }) => { failOpenidGet = err; },
    __failOpenidPut: (err: { name: string; message: string }) => { failOpenidPut = err; },
  },
};
