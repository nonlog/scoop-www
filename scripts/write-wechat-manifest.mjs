import { readFile, writeFile } from 'node:fs/promises';

const metadataPath = process.argv[2] || 'wechat-metadata.json';
const repository = process.argv[3] || 'nonlog/scoop-www';
const metadata = JSON.parse(await readFile(metadataPath, 'utf8'));
if (!metadata.changed) process.exit(0);

const path = 'bucket/wechat.json';
const manifest = JSON.parse(await readFile(path, 'utf8'));
manifest.version = metadata.version;
manifest.url = `https://github.com/${repository}/releases/download/wechat-${metadata.version}/WeChat-${metadata.version}.exe#/dl.7z`;
manifest.hash = metadata.sha256;
await writeFile(path, `${JSON.stringify(manifest, null, 4)}\n`, 'utf8');
