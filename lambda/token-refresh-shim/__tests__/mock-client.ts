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

const reset = () => {
  store = {};
  listNames = [];
  failOpName = null;
  failOpError = null;
  putCount = 0;
  failOnPutFrom = -1;
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
      if (failOnPutFrom > 0 && putCount >= failOnPutFrom && failOpError) {
        const err: any = new Error(failOpError.message);
        err.name = failOpError.name;
        return Promise.reject(err);
      }
      store[cmd.input.SecretId] = cmd.input.SecretString;
      return Promise.resolve({ ARN: 'arn', VersionId: 'v' });
    }

    if (cmd instanceof CreateSecretCommand) {
      store[cmd.input.Name] = cmd.input.SecretString;
      return Promise.resolve({ ARN: 'arn' });
    }

    if (cmd instanceof GetSecretValueCommand) {
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

// Test helpers attached to the module export so tests can drive the mock.
export const mockClient = {
  reset,
  secretsManager: {
    SecretsManagerClient,
    GetSecretValueCommand,
    PutSecretValueCommand,
    CreateSecretCommand,
    ListSecretsCommand,
    __set: (id: string, value: string) => { store[id] = value; },
    __listNames: (names: string[]) => { listNames = names; },
    __failOn: (op: string, err: { name: string; message: string }) => { failOpName = op; failOpError = err; },
    __failOnPutFrom: (n: number, err: { name: string; message: string }) => { failOnPutFrom = n; failOpError = err; },
  },
  dynamodb: {
    DynamoDBDocumentClient: { from: () => ({ send: () => Promise.resolve({}) }) },
    PutCommand: class { constructor(public input: any) {} },
    DeleteCommand: class { constructor(public input: any) {} },
  },
};
