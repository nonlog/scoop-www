import { createHash } from 'node:crypto';
import { createReadStream, createWriteStream } from 'node:fs';
import { mkdir, readFile, stat, writeFile } from 'node:fs/promises';
import { dirname, resolve } from 'node:path';
import { pipeline } from 'node:stream/promises';
import vm from 'node:vm';

const ROOT_URL = 'https://423down.lanzouo.com/b0f1ada0f';
const ROOT_ORIGIN = new URL(ROOT_URL).origin;
const USER_AGENT = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/131 Safari/537.36';

function argument(name, fallback) {
    const index = process.argv.indexOf(name);
    return index >= 0 && process.argv[index + 1] ? process.argv[index + 1] : fallback;
}

const manifestPath = argument('--manifest', 'bucket/wechat.json');
const outputPath = argument('--output', 'wechat.exe');
const metadataPath = argument('--metadata', 'wechat-metadata.json');

function versionParts(version) {
    return String(version || '').split('.').map((part) => Number.parseInt(part, 10) || 0);
}

function compareVersions(left, right) {
    const a = versionParts(left);
    const b = versionParts(right);
    for (let index = 0; index < Math.max(a.length, b.length); index += 1) {
        if ((a[index] || 0) !== (b[index] || 0)) return (a[index] || 0) - (b[index] || 0);
    }
    return 0;
}

function sourceVersion(fileName) {
    const match = String(fileName).match(/\u5fae\u4fe1\u6b63\u5f0f\u7248\s*v?([\d]+(?:\.[\d]+)+).*\.exe$/i);
    return match ? match[1] : null;
}

function headers(extra = {}) {
    return {
        'User-Agent': USER_AGENT,
        Accept: '*/*',
        ...extra,
    };
}

async function request(url, options = {}, timeoutMs = 60_000) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);
    try {
        const response = await fetch(url, { ...options, signal: controller.signal });
        if (!response.ok) {
            const body = await response.text().catch(() => '');
            throw new Error(`HTTP ${response.status} from ${url}: ${body.slice(0, 200)}`);
        }
        return response;
    } finally {
        clearTimeout(timer);
    }
}

async function text(url, options = {}, timeoutMs = 60_000) {
    return (await request(url, options, timeoutMs)).text();
}

async function form(url, values, referer, extraHeaders = {}) {
    const body = new URLSearchParams(values);
    const response = await request(url, {
        method: 'POST',
        headers: headers({
            Referer: referer,
            Origin: new URL(url).origin,
            'X-Requested-With': 'XMLHttpRequest',
            'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
            ...extraHeaders,
        }),
        body,
    });
    return response.json();
}

function calculateChallengeCookie(script) {
    let cookie = '';
    const document = {
        location: { reload() {} },
        get cookie() {
            return cookie;
        },
        set cookie(value) {
            cookie = value;
        },
    };
    const sandbox = { document, console: { log() {}, warn() {}, error() {} } };
    sandbox.window = sandbox;
    vm.runInNewContext(script, sandbox, { timeout: 5_000 });
    const value = cookie.split(';', 1)[0];
    if (!value) throw new Error('Lanzou anti-bot cookie was not produced');
    return value;
}

async function sha256(filePath) {
    const hash = createHash('sha256');
    for await (const chunk of createReadStream(filePath)) hash.update(chunk);
    return hash.digest('hex');
}

async function writeMetadata(metadata) {
    await mkdir(dirname(resolve(metadataPath)), { recursive: true });
    await writeFile(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`, 'utf8');
}

const delay = (milliseconds) => new Promise((resolvePromise) => setTimeout(resolvePromise, milliseconds));

const manifest = JSON.parse(await readFile(manifestPath, 'utf8'));
const rootPage = await text(ROOT_URL, { headers: headers() });
const lookupFile = rootPage.match(/url\s*:\s*'\/filemoreajax\.php\?file=(\d+)'/)?.[1];
const uid = rootPage.match(/'uid':'([^']+)'/)?.[1];
const puid = rootPage.match(/'puid':'([^']+)'/)?.[1];
const timestamp = rootPage.match(/var\s+[A-Za-z_$][\w$]*\s*=\s*'(\d{10,})'/)?.[1];
const key = rootPage.match(/var\s+[A-Za-z_$][\w$]*\s*=\s*'([a-f0-9]{32})'/i)?.[1];
if (!lookupFile || !uid || !puid || !timestamp || !key) throw new Error('Could not parse the Lanzou root listing page');

const listing = await form(`${ROOT_ORIGIN}/filemoreajax.php?file=${lookupFile}`, {
    lx: '2',
    fid: lookupFile,
    uid,
    puid,
    pg: '1',
    rep: '0',
    t: timestamp,
    k: key,
    up: '1',
    vip: '0',
    webfoldersign: '',
}, ROOT_URL);
if (listing.zt !== 1 || !Array.isArray(listing.text)) throw new Error(`Lanzou listing failed: ${JSON.stringify(listing)}`);

const candidates = listing.text
    .map((item) => ({ ...item, version: sourceVersion(item.name_all) }))
    .filter((item) => item.version && item.id)
    .sort((left, right) => compareVersions(right.version, left.version));
const latest = candidates[0];
if (!latest) throw new Error('No modified WeChat executable was found in the Lanzou root listing');

const metadata = {
    changed: compareVersions(latest.version, manifest.version) > 0,
    version: latest.version,
    source_name: latest.name_all,
    source_size: latest.size,
};
if (!metadata.changed) {
    await writeMetadata(metadata);
    console.log(`Source is ${latest.version}; manifest is already ${manifest.version}.`);
} else {
    const filePageUrl = `${ROOT_ORIGIN}/${latest.id}`;
    const challengePage = await text(filePageUrl, { headers: headers({ Referer: ROOT_URL }) });
    const challengeScript = challengePage.match(/<script>([\s\S]*?)<\/script>/i)?.[1];
    if (!challengeScript) throw new Error('Lanzou download challenge was not found');
    const cookie = calculateChallengeCookie(challengeScript);
    const filePage = await text(filePageUrl, { headers: headers({ Referer: ROOT_URL, Cookie: cookie }) });
    const iframePath = filePage.match(/<iframe[^>]+src="([^"]+)"/i)?.[1];
    if (!iframePath) throw new Error('Lanzou file page did not expose its download iframe');

    const iframeUrl = new URL(iframePath, ROOT_ORIGIN).href;
    const iframePage = await text(iframeUrl, { headers: headers({ Referer: filePageUrl, Cookie: cookie }) });
    const ajaxFile = iframePage.match(/\/ajaxfile\.php\?file=(\d+)/)?.[1];
    const webSign = iframePage.match(/var ajaxdata\s*=\s*'([^']+)'/)?.[1];
    const webSignValue = iframePage.match(/var wp_sign\s*=\s*'([^']+)'/)?.[1];
    if (!ajaxFile || !webSign || !webSignValue) throw new Error('Could not parse the Lanzou download token page');

    const token = await form(`${ROOT_ORIGIN}/ajaxfile.php?file=${ajaxFile}`, {
        action: 'downprocess',
        websignkey: webSign,
        signs: webSign,
        sign: webSignValue,
        websign: '',
        kd: '0',
        ves: '1',
    }, filePageUrl, { Cookie: cookie });
    if (token.zt !== 1 || !token.dom || !token.url) throw new Error(`Lanzou token request failed: ${JSON.stringify(token)}`);

    const verificationUrl = `${token.dom}/file/${token.url}`;
    const verificationPage = await text(verificationUrl, { headers: headers({ Referer: filePageUrl }) });
    const downloadFile = verificationPage.match(/'file':'([^']+)'/)?.[1];
    const downloadSign = verificationPage.match(/'sign':'([^']+)'/)?.[1];
    if (!downloadFile || !downloadSign) throw new Error('Lanzou verification page did not expose its token');

    // Lanzou rejects immediate verification requests with ?SignError.
    await delay(2_000);
    const verified = await form(new URL('ajax.php', verificationUrl).href, {
        file: downloadFile,
        el: '2',
        sign: downloadSign,
    }, verificationUrl);
    if (verified.zt !== 1 || !verified.url) throw new Error(`Lanzou verification failed: ${JSON.stringify(verified)}`);
    if (verified.url.startsWith('?')) throw new Error(`Lanzou returned an invalid download URL: ${verified.url}`);

    await mkdir(dirname(resolve(outputPath)), { recursive: true });
    const download = await request(verified.url, { headers: headers({ Referer: verificationUrl }) }, 30 * 60_000);
    if (!download.body) throw new Error('Download response did not contain a body');
    await pipeline((await import('node:stream')).Readable.fromWeb(download.body), createWriteStream(outputPath));
    const fileStats = await stat(outputPath);
    metadata.sha256 = await sha256(outputPath);
    metadata.download_size = fileStats.size;
    metadata.changed = true;
    await writeMetadata(metadata);
    console.log(JSON.stringify(metadata, null, 2));
}
