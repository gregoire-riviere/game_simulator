import { mkdir, copyFile, readFile, writeFile } from 'node:fs/promises';
const output = new URL('../web/assets/vendor/', import.meta.url);
const three = new URL('../node_modules/three/', import.meta.url);
await mkdir(output, { recursive: true });
await copyFile(new URL('build/three.module.min.js', three), new URL('three.module.js', output));
await copyFile(new URL('LICENSE', three), new URL('THREE-LICENSE.txt', output));
const controls = await readFile(new URL('examples/jsm/controls/OrbitControls.js', three), 'utf8');
await writeFile(new URL('OrbitControls.js', output), controls.replace("from 'three'", "from './three.module.js'"));
