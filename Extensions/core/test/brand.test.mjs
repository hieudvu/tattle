import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectChromiumBrand } from '../src/webext/brand.js';

const CHROME_UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0 Safari/537.36';

test('plain Chrome UA maps to chrome', async () => {
  assert.equal(await detectChromiumBrand({ userAgent: CHROME_UA }), 'chrome');
});

test('Edge is identified by the Edg/ token', async () => {
  assert.equal(await detectChromiumBrand({ userAgent: `${CHROME_UA} Edg/130.0.0.0` }), 'edge');
});

test('Opera is identified by the OPR/ token', async () => {
  assert.equal(await detectChromiumBrand({ userAgent: `${CHROME_UA} OPR/115.0.0.0` }), 'opera');
});

test('Vivaldi is identified by its token', async () => {
  assert.equal(await detectChromiumBrand({ userAgent: `${CHROME_UA} Vivaldi/6.0` }), 'vivaldi');
});

test('Brave wins when navigator.brave.isBrave() resolves true', async () => {
  const nav = { userAgent: `${CHROME_UA} Edg/130`, brave: { isBrave: async () => true } };
  assert.equal(await detectChromiumBrand(nav), 'brave');
});

test('a Brave API that resolves false falls through to the UA check', async () => {
  const nav = { userAgent: `${CHROME_UA} Edg/130`, brave: { isBrave: async () => false } };
  assert.equal(await detectChromiumBrand(nav), 'edge');
});

test('a Brave API that throws is ignored', async () => {
  const nav = { userAgent: CHROME_UA, brave: { isBrave: async () => { throw new Error('x'); } } };
  assert.equal(await detectChromiumBrand(nav), 'chrome');
});

test('missing navigator data falls back to chrome', async () => {
  assert.equal(await detectChromiumBrand(undefined), 'chrome');
  assert.equal(await detectChromiumBrand({}), 'chrome');
});
