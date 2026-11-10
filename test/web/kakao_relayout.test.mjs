// Runs the relayout helper from web/index.html against a fake Kakao SDK:  node --test test/web/kakao_relayout.test.mjs
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../../web/index.html', import.meta.url), 'utf8');
const m = html.match(/<script>\s*\/\/ Kakao web map resize support[\s\S]*?<\/script>/);
assert.ok(m, 'the relayout script is in web/index.html');
const script = m[0].replace(/^<script>/, '').replace(/<\/script>$/, '');

function sandbox() {
  const ctx = { setInterval, clearInterval, setTimeout, console };
  ctx.window = ctx;
  ctx.document = { body: { contains: (n) => n.attached } };
  vm.createContext(ctx);
  vm.runInContext(script, ctx);
  return ctx;
}

// A fake SDK map: relayout() re-measures and (like a resize does) drifts the centre, unless the helper restores it.
function installSdk(ctx) {
  ctx.kakao = {
    maps: {
      Map: class FakeMap {
        constructor(node, options) {
          this.node = node; this.center = options.center; this.level = options.level; this.relayouts = 0;
          FakeMap.all.push(this);
        }
        getNode() { return this.node; }
        getCenter() { return this.center; }
        setCenter(c) { this.center = c; }
        getLevel() { return this.level; }
        setLevel(l) { this.level = l; }
        relayout() { this.relayouts++; this.center = { lat: 0, lng: 0 }; this.level = 14; }
      },
    },
  };
  ctx.kakao.maps.Map.all = [];
  return ctx.kakao.maps.Map.all;
}
const wait = (ms) => new Promise((r) => setTimeout(r, ms));

test('a resize re-measures the map and keeps the selected university, zoom and manual pan', async () => {
  const ctx = sandbox();
  const all = installSdk(ctx);
  await wait(60); // the helper wraps the constructor as soon as the SDK defines it
  const node = { attached: true };
  const map = new ctx.kakao.maps.Map(node, { center: { lat: 36.77, lng: 126.93 }, level: 4 });
  assert.equal(all.length, 1);
  map.setCenter({ lat: 36.78, lng: 126.95 }); // the user panned
  map.setLevel(5); //                            and zoomed
  ctx.__meogeobojoRelayout();
  assert.equal(map.relayouts, 1);
  assert.deepEqual(map.center, { lat: 36.78, lng: 126.95 });
  assert.equal(map.level, 5);
});

test('maps that left the page are forgotten; a missing SDK or no map is harmless', async () => {
  const ctx = sandbox();
  ctx.__meogeobojoRelayout(); // nothing created yet
  installSdk(ctx);
  await wait(60);
  const gone = new ctx.kakao.maps.Map({ attached: true }, { center: {}, level: 3 });
  const kept = new ctx.kakao.maps.Map({ attached: true }, { center: { a: 1 }, level: 3 });
  gone.node.attached = false;
  ctx.__meogeobojoRelayout();
  assert.equal(gone.relayouts, 0);
  assert.equal(kept.relayouts, 1);
  ctx.__meogeobojoRelayout();
  assert.equal(kept.relayouts, 2);
});

test('constructing a map still behaves like the original constructor', async () => {
  const ctx = sandbox();
  installSdk(ctx);
  await wait(60);
  const map = new ctx.kakao.maps.Map({ attached: true }, { center: { lat: 1 }, level: 4 });
  assert.equal(map.level, 4);
  assert.ok(map instanceof ctx.kakao.maps.Map);
});
