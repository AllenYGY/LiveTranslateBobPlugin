const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');
const info = JSON.parse(fs.readFileSync(path.join(__dirname, '../plugin/info.json')));
assert.strictEqual(info.name, 'Live Translate');
assert.strictEqual(info.category, 'translate');
assert.ok(info.options.some(o => o.identifier === 'deepgram_api_key' && o.textConfig.type === 'secure'));
assert.strictEqual(info.options.find(o => o.identifier === 'translation_backend').defaultValue, 'apple');
const requests = [];
let timer;
let cancelled;
const context = {
  $option: { deepgram_api_key: 'test-key', translation_backend: 'apple' },
  $http: { request: req => { requests.push(req); } },
  $timer: { schedule: options => { timer = options; return 7; }, invalidate: id => assert.strictEqual(id, 7) }
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../plugin/main.js'), 'utf8'), context);
assert.strictEqual(context.pluginTimeoutInterval(), 300);
let streams = [];
let completion;
context.translate({ text: '/live', onStream: value => streams.push(value), onCompletion: value => { completion = value; },
  cancelSignal: { subscribe: handler => { cancelled = handler; return { dispose() {} }; } } });
assert.strictEqual(requests[0].url, 'http://127.0.0.1:17764/start');
assert.strictEqual(requests[0].body.deepgramKey, 'test-key');
assert.strictEqual(requests[0].body.backend, 'apple');
requests[0].handler({ data: { ok: true, session: 'test-session' } });
assert.strictEqual(requests[1].url, 'http://127.0.0.1:17764/snapshot');
requests[1].handler({ data: { ok: true, running: true, segments: [{ source: 'Hello', translation: '你好' }] } });
assert.strictEqual(streams[0].content.format, 'markdown');
assert.strictEqual(streams[0].content.text, '> Hello\n\n### 你好');
timer.handler();
requests[2].handler({ data: { ok: true, running: true, segments: [{ source: 'Hello', translation: '你好' }], interim: 'World' } });
assert.strictEqual(streams[1].content.text, '> Hello\n\n### 你好\n\n---\n\n> 🎙 World\n\n### 识别中…');
const rolling = context.render({ segments: [
  { source: 'Old 1', translation: '旧一' },
  { source: 'Old 2', translation: '旧二' },
  { source: 'New 3', translation: '新三' }
] });
assert.ok(!rolling.includes('Old 1'));
assert.ok(rolling.includes('Old 2') && rolling.includes('New 3'));
assert.ok(context.render({ segments: [{ source: '*Hello*', translation: '#你好' }] }).includes('\\*Hello\\*'));
cancelled();
assert.strictEqual(requests[3].url, 'http://127.0.0.1:17764/stop');
assert.strictEqual(requests[3].body.session, 'test-session');
assert.strictEqual(completion, undefined);
context.$option.deepgram_api_key = '';
context.translate({ text: '/live', onCompletion: value => { completion = value; } });
assert.strictEqual(completion.error.type, 'secretKey');
context.$option.deepgram_api_key = 'test-key';
context.translate({ text: '/live', onStream() {}, onCompletion() {},
  cancelSignal: { subscribe: handler => { cancelled = handler; return { dispose() {} }; } } });
const pending = requests[4];
cancelled();
pending.handler({ data: { ok: true, session: 'late-session' } });
assert.strictEqual(requests[5].url, 'http://127.0.0.1:17764/stop');
assert.strictEqual(requests[5].body.session, 'late-session');
context.translate({ text: 'live', onStream() {}, onCompletion() {} });
assert.strictEqual(requests[6].url, 'http://127.0.0.1:17764/start');
let stopResult;
context.translate({ text: 'stop', onCompletion: value => { stopResult = value; } });
assert.strictEqual(requests[7].url, 'http://127.0.0.1:17764/stop');
requests[7].handler({ data: { ok: true } });
assert.strictEqual(stopResult.result.content.text, '实时翻译已停止。');
