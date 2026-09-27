const fs = require('fs');
const path = require('path');
const vm = require('vm');
const assert = require('assert');

const source = fs.readFileSync(path.join(__dirname, '../plugin/main.js'), 'utf8');
let request;
const context = {
  $option: { api_key: 'test-key', base_url: 'https://api.deepseek.com/v1', model: 'deepseek-chat' },
  $http: { request: value => { request = value; value.handler({ data: { choices: [{ message: { content: '你好，同学们。' } }] } }); } }
};
vm.createContext(context);
vm.runInContext(source, context);
let callback;
context.translate({ text: 'Hello class.', detectFrom: 'en', onCompletion: value => { callback = value; } });
assert.strictEqual(request.url, 'https://api.deepseek.com/v1/chat/completions');
assert.strictEqual(request.body.messages[1].content, 'Hello class.');
assert.strictEqual(callback.result.content.text, '你好，同学们。');
assert.strictEqual(callback.result.to, 'zh-Hans');
context.$option.api_key = '';
context.translate({ text: 'Hello', detectFrom: 'en', onCompletion: value => { callback = value; } });
assert.strictEqual(callback.error.type, 'secretKey');
context.$option.api_key = 'test-key';
context.$http.request = value => value.handler({ error: 'network failed' });
context.translate({ text: 'Hello', detectFrom: 'en', onCompletion: value => { callback = value; } });
assert.strictEqual(callback.error.type, 'network');
