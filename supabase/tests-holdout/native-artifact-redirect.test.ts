import assert from 'node:assert/strict';
import { afterAll, test } from 'vitest';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import { createHash } from 'node:crypto';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
import { resolve, join } from 'node:path';
import { pathToFileURL } from 'node:url';
import ts from 'typescript';

const heldRequire = createRequire(import.meta.url);
const heldRoot = 'C:/fr-sealed-20261007/artifact-redirect-held';
const heldLog = join(heldRoot, `run-${Date.now()}.log`);
await mkdir(heldRoot, { recursive: true });
const heldPython = 'C:/Users/Harsh/AppData/Local/hermes/hermes-agent/venv/Scripts/python.exe';
const heldWorkflow = resolve('.github/workflows/db.yml');
const heldConstants = await readFile(resolve('packages/shared/src/config/constants.ts'), 'utf8');
const heldLimits = (await import(pathToFileURL(resolve('packages/shared/src/config/constants.ts')).href)).NATIVE_DB_VALIDATION;
const heldMetadata = { total: 0, passed: 0, failed: 0 };

async function executeHeldNativeArtifactReader(variation = {}) {
  const state = { api: [], storage: [], deadlines: [], timers: [], archiveReaders: 0 };
  const value = { formatVersion: 1, custody: 'controlled', complete: true };
  const filename = 'fixture.json';
  const canonical = Buffer.from(`${JSON.stringify(value)}\n`, 'utf8');
  const body = variation.noncanonical ? Buffer.from(`${JSON.stringify(value, null, '  ')}\n`) : canonical;
  const zipBytes = execFileSync(heldPython, ['-c', String.raw`
import io, json, stat, sys, zipfile
request=json.loads(sys.stdin.buffer.read())
sink=io.BytesIO()
with zipfile.ZipFile(sink, 'w') as archive:
    names=[request['filename']]
    if request['extra']: names.append('additional.json')
    if request['wrong']: names=['other.json']
    for name in names:
        item=zipfile.ZipInfo(name)
        item.create_system=3
        item.external_attr=(stat.S_IFREG | 0o600) << 16
        item.compress_type=zipfile.ZIP_STORED
        archive.writestr(item, request['body'].encode('utf8'))
sys.stdout.buffer.write(sink.getvalue())
`,], { input: JSON.stringify({ filename, body: body.toString('utf8'), extra: !!variation.extraMember, wrong: !!variation.wrongMember }), maxBuffer: heldLimits.timeoutQueryMaxBytes });
  const archiveSha256 = createHash('sha256').update(zipBytes).digest('hex');
  const artifact = Object.freeze({ id: 913, size_in_bytes: zipBytes.length + (variation.sizeDelta ?? 0), expired: variation.expired ?? false, digest: `sha256:${variation.badDigest ? 'f'.repeat(heldLimits.digestHexLength) : archiveSha256}` });
  const immutableBefore = JSON.stringify(artifact);
  const location = variation.location ?? 'https://storage.example.invalid/owned/fixture.zip?signature=controlled';
  const timeoutSignal = milliseconds => {
    state.deadlines.push(milliseconds);
    const controller = new AbortController();
    if (variation.abortApi) queueMicrotask(() => controller.abort(new Error('Controlled deadline.')));
    return controller.signal;
  };
  const apiFetch = async (url, options = {}) => {
    state.api.push({ url: String(url), options });
    if (variation.abortApi && options.signal) {
      return new Promise((_, reject) => {
        if (options.signal.aborted) reject(options.signal.reason);
        else options.signal.addEventListener('abort', () => reject(options.signal.reason), { once: true });
      });
    }
    const status = options.redirect === 'manual' ? (variation.apiStatus ?? 302) : 200;
    state.api[state.api.length - 1].status = status;
    return new Response(null, { status, headers: variation.noLocation ? {} : { location } });
  };
  const sdkDownload = async (...arguments_) => {
    const options = typeof arguments_[0] === 'string' ? arguments_[1] : arguments_[0];
    const selectedFetch = options?.request?.fetch ?? apiFetch;
    const response = await selectedFetch('https://api.github.com/repos/OGUN01/gymloop/actions/artifacts/913/zip', {
      method: 'GET', headers: { authorization: 'token synthetic-api-only' },
      ...(options?.request?.signal ? { signal: options.request.signal } : {}),
    });
    return { status: response.status, headers: Object.fromEntries(response.headers), data: null };
  };
  const github = { request: sdkDownload, rest: { actions: { downloadArtifact: sdkDownload } } };
  const storageFetch = async (url, options = {}) => {
    state.storage.push({ url: String(url), options });
    if (variation.networkFailure) throw new Error('Controlled storage failure.');
    if (variation.storageRedirect) {
      if (options.redirect === 'error') throw new TypeError('Controlled storage redirect.');
      return new Response(zipBytes, { status: 200 });
    }
    const delivered = variation.truncated ? zipBytes.subarray(0, zipBytes.length - 1) : zipBytes;
    return new Response(delivered, { status: variation.storageStatus ?? 200, headers: { 'content-length': String(delivered.length) } });
  };
  const fetchPort = (url, options) => String(url).startsWith('https://api.github.com/') ? apiFetch(url, options) : storageFetch(url, options);
  const source = await readFile(heldWorkflow, 'utf8');
  const lines = source.replaceAll('\r\n', '\n').split('\n');
  const step = lines.findIndex(line => {
    const match = line.trim().match(/^(?:-\s*)?name:\s*(.+)$/);
    if (!match) return false;
    const name = match[1].replace(/^(['"])(.*)\1$/, '$2').replaceAll("''", "'").replaceAll('\u2019', "'");
    return name === "Require the previous armed attempt's verified restoration";
  });
  if (step < 0) throw Object.assign(new Error('Held extraction target unavailable.'), { code: 'HELD_INFRASTRUCTURE' });
  const script = lines.findIndex((line, index) => index > step && /^\s+script:\s*\|\s*$/.test(line));
  if (script < 0) throw Object.assign(new Error('Held script declaration unavailable.'), { code: 'HELD_INFRASTRUCTURE' });
  const indent = lines[script].match(/^\s*/)[0].length;
  const content = [];
  for (let index = script + 1; index < lines.length; index += 1) {
    if (lines[index].trim() && lines[index].match(/^\s*/)[0].length <= indent) break;
    content.push(lines[index].slice(indent + 2));
  }
  const parsed = ts.createSourceFile('held-inline.js', content.join('\n'), ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const declarations = new Map();
  for (const statement of parsed.statements) {
    if (ts.isFunctionDeclaration(statement) && statement.name) declarations.set(statement.name.text, statement);
    if (ts.isVariableStatement(statement)) for (const declaration of statement.declarationList.declarations) {
      if (ts.isIdentifier(declaration.name)) declarations.set(declaration.name.text, declaration);
      if (ts.isObjectBindingPattern(declaration.name)) for (const element of declaration.name.elements) if (ts.isIdentifier(element.name)) declarations.set(element.name.text, declaration);
    }
  }
  const needed = new Set();
  const scan = [declarations.get('readArtifact')];
  if (!scan[0]) throw Object.assign(new Error('Held reader declaration unavailable.'), { code: 'HELD_INFRASTRUCTURE' });
  while (scan.length) {
    const declaration = scan.pop();
    if (needed.has(declaration)) continue;
    needed.add(declaration);
    const bound = new Set();
    const bind = node => {
      if ((ts.isVariableDeclaration(node) || ts.isParameter(node) || ts.isFunctionDeclaration(node)) && node.name && ts.isIdentifier(node.name)) bound.add(node.name.text);
      ts.forEachChild(node, bind);
    };
    bind(declaration);
    const references = node => {
      if (ts.isIdentifier(node) && !bound.has(node.text)) {
        const parent = node.parent;
        const memberName = ts.isPropertyAccessExpression(parent) && parent.name === node;
        const objectName = ts.isPropertyAssignment(parent) && parent.name === node;
        if (!memberName && !objectName && declarations.has(node.text)) scan.push(declarations.get(node.text));
      }
      ts.forEachChild(node, references);
    };
    references(declaration);
  }
  const selected = [...needed].sort((left, right) => left.pos - right.pos).map(node => ts.isVariableDeclaration(node) ? `const ${node.getText(parsed)};` : node.getText(parsed)).join('\n');
  const executionAst = ts.createSourceFile('held-execution.js', selected, ts.ScriptTarget.Latest, true, ts.ScriptKind.JS);
  const transformed = ts.transform(executionAst, [context => {
    const visitor = node => ts.isCallExpression(node) && node.expression.kind === ts.SyntaxKind.ImportKeyword
      ? ts.factory.createCallExpression(ts.factory.createIdentifier('heldImport'), undefined, node.arguments)
      : ts.visitEachChild(node, visitor, context);
    return node => ts.visitNode(node, visitor);
  }]);
  const execution = ts.createPrinter().printFile(transformed.transformed[0]);
  transformed.dispose();
  const requirePort = name => {
    if (name === 'node:child_process' || name === 'child_process') return {
      execFileSync: (command, arguments_, options) => {
        state.archiveReaders += 1;
        return execFileSync(command === 'python3' ? heldPython : command, arguments_, options);
      },
    };
    if (name === 'node:fs' || name === 'fs') return {
      readFileSync: path => {
        if (!String(path).replaceAll('\\', '/').endsWith('packages/shared/src/config/constants.ts')) throw new Error('Held file read refused.');
        return heldConstants;
      },
    };
    return heldRequire(name);
  };
  const timerPort = (callback, milliseconds) => {
    state.deadlines.push(milliseconds);
    const timer = setTimeout(callback, variation.abortApi ? 1 : milliseconds); state.timers.push(timer); return timer;
  };
  const runner = new Function('github', 'context', 'core', 'fetch', 'require', 'Buffer', 'URL', 'AbortSignal', 'AbortController', 'setTimeout', 'clearTimeout', 'artifactInput', 'filenameInput', 'heldImport',
    `return (async () => { ${execution}\nreturn await readArtifact(artifactInput, filenameInput); })();`);
  try {
    const result = await runner(github, { repo: { owner: 'OGUN01', repo: 'gymloop' } }, { setFailed: () => { throw new Error('Held surrounding workflow refused.'); } }, fetchPort, requirePort, Buffer, URL,
      { timeout: timeoutSignal, any: signals => AbortSignal.any(signals) }, AbortController, timerPort, clearTimeout, artifact, filename,
      specifier => import(typeof specifier === 'string' && /^[A-Za-z]:[\\/]/.test(specifier) ? pathToFileURL(specifier).href : specifier));
    assert.equal(JSON.stringify(artifact), immutableBefore);
    return { result, state, expected: { value, hash: createHash('sha256').update(canonical).digest('hex'), archiveSha256 } };
  } catch (error) {
    if (error instanceof ReferenceError || error instanceof SyntaxError || error.code === 'ENOENT' || error.code === 'ERR_UNSUPPORTED_ESM_URL_SCHEME') error.code = 'HELD_INFRASTRUCTURE';
    error.heldTransportState = { apiRequests: state.api.length, firstApiMode: state.api[0]?.options?.redirect ?? null, firstApiStatus: state.api[0]?.status ?? null, storageRequests: state.storage.length, archiveReaders: state.archiveReaders, deadlines: state.deadlines };
    throw error;
  } finally { for (const timer of state.timers) clearTimeout(timer); }
}

for (const scenario of [
  { name: 'valid exact archive and immutable artifact', variation: {}, positive: true },
  { name: 'manual API redirect and bounded real signal', variation: {}, positive: true, transport: true },
  { name: 'storage error redirects without API authorization', variation: {}, positive: true, storage: true },
  { name: 'automatic first200 refused', variation: { apiStatus: 200 } },
  { name: 'missing Location refused', variation: { noLocation: true } },
  { name: 'insecure storage URL refused', variation: { location: 'http://storage.example.invalid/fixture.zip' } },
  { name: 'credential-bearing storage URL refused', variation: { location: 'https://held:password@storage.example.invalid/fixture.zip' } },
  { name: 'fragment storage URL refused', variation: { location: 'https://storage.example.invalid/fixture.zip#part' } },
  { name: 'API abort refuses stalled acquisition', variation: { abortApi: true } },
  { name: 'storage redirect refused', variation: { storageRedirect: true } },
  { name: 'storage network failure refused', variation: { networkFailure: true } },
  { name: 'storage status failure refused', variation: { storageStatus: 403 } },
  { name: 'exact API size required', variation: { sizeDelta: 1 } },
  { name: 'exact API digest required', variation: { badDigest: true } },
  { name: 'expired artifact refused', variation: { expired: true } },
  { name: 'truncated archive refused', variation: { truncated: true } },
  { name: 'single exact archive member required', variation: { extraMember: true } },
  { name: 'wrong archive member refused', variation: { wrongMember: true } },
  { name: 'canonical JSON bytes required', variation: { noncanonical: true } },
]) {
  test(scenario.name, async () => {
    heldMetadata.total += 1;
    try {
      if (!scenario.positive) await assert.rejects(executeHeldNativeArtifactReader(scenario.variation), error => error.code !== 'HELD_INFRASTRUCTURE');
      else {
        const observed = await executeHeldNativeArtifactReader(scenario.variation);
        assert.deepEqual(observed.result, observed.expected);
        assert.equal(observed.state.archiveReaders, 1);
        if (scenario.transport) {
          assert.equal(observed.state.api.length, 1);
          assert.equal(observed.state.api[0].options.redirect, 'manual');
          assert.ok(observed.state.api[0].options.signal instanceof AbortSignal);
          assert.ok(observed.state.deadlines.some(value => Number.isSafeInteger(value) && value > 0 && value <= heldLimits.nativeCleanupReserveMs));
        }
        if (scenario.storage) {
          assert.equal(observed.state.storage.length, 1);
          assert.equal(observed.state.storage[0].options.redirect, 'error');
          assert.equal(new Headers(observed.state.storage[0].options.headers).has('authorization'), false);
          assert.ok(observed.state.storage[0].options.signal instanceof AbortSignal);
        }
      }
      heldMetadata.passed += 1;
    } catch (error) {
      heldMetadata.failed += 1;
      await writeFile(heldLog, `${scenario.name}: ${error.stack}\n${JSON.stringify(error.heldTransportState ?? null)}\n`, { flag: 'a' });
      throw new Error('Held transport check failed.');
    }
  });
}
afterAll(async () => {
  const source = await readFile(resolve('supabase/tests-holdout/native-artifact-redirect.test.ts'));
  const diagnostics = await readFile(heldLog).catch(() => Buffer.from('HELD_PASS\n'));
  process.stdout.write(`${JSON.stringify({ suite: 'native-artifact-redirect-held', ...heldMetadata, verdict: heldMetadata.failed ? 'FAIL' : 'PASS', testSha256: createHash('sha256').update(source).digest('hex'), privateLogSha256: createHash('sha256').update(diagnostics).digest('hex') })}\n`);
});
