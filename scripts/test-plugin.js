const fs = require('fs');
const path = require('path');
const vm = require('vm');
const crypto = require('crypto');
const assert = require('assert');

const source = fs.readFileSync(path.join(__dirname, '../plugin/main.js'), 'utf8');
const word = bytes => ({ bytes, toString: () => bytes.toString('hex') });
const CryptoJS = {
  enc: { Hex: {} },
  SHA256: value => word(crypto.createHash('sha256').update(value).digest()),
  HmacSHA256: (value, key) => word(crypto.createHmac('sha256', key.bytes || key).update(value).digest())
};
let request;
const context = {
  require: name => { assert.strictEqual(name, 'crypto-js'); return CryptoJS; },
  $data: { fromUTF8: value => ({ text: value }) },
  $option: { access_key_id: 'test-id', secret_access_key: 'test-secret' },
  $http: { request: value => { request = value; value.handler({ data: { TranslationList: [{ Translation: '你好，同学们。' }] } }); } }
};
vm.createContext(context);
vm.runInContext(source, context);
const body = JSON.stringify({ TargetLanguage: 'zh', TextList: ['Hello class.'] });
const signed = context.signRequest(body, 'test-id', 'test-secret', new Date('2026-09-27T01:02:03Z'));
assert.strictEqual(signed['X-Date'], '20260927T010203Z');
assert.ok(signed.Authorization.endsWith('Signature=da15850d2eb97a907e457b637cc89305e1b9ef9793e5360ed6e6e7005443518a'));
let callback;
context.translate({ text: 'Hello class.', detectFrom: 'en', onCompletion: value => { callback = value; } });
assert.strictEqual(request.url, 'https://translate.volcengineapi.com/?Action=TranslateText&Version=2020-06-01');
assert.strictEqual(request.body.text, body);
assert.strictEqual(callback.result.content.text, '你好，同学们。');
assert.strictEqual(callback.result.to, 'zh-Hans');
context.$option.secret_access_key = '';
context.translate({ text: 'Hello', detectFrom: 'en', onCompletion: value => { callback = value; } });
assert.strictEqual(callback.error.type, 'secretKey');
context.$option.secret_access_key = 'test-secret';
context.$http.request = value => value.handler({ error: 'network failed' });
context.translate({ text: 'Hello', detectFrom: 'en', onCompletion: value => { callback = value; } });
assert.strictEqual(callback.error.type, 'network');
