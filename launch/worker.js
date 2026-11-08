// Static assets ignore Range headers; serve byte ranges for Safari video playback.
const RANGE = /^bytes=(\d*)-(\d*)$/;

export default {
  async fetch(request, env) {
    const requestHeaders = new Headers(request.headers);
    requestHeaders.delete('Range');
    requestHeaders.delete('If-Range');
    const asset = await env.ASSETS.fetch(new Request(request.url, {method: 'GET', headers: requestHeaders}));
    const range = request.headers.get('Range');
    if (asset.status !== 200 || request.method !== 'GET' || !range || range.includes(',')) {
      return withRanges(asset, request.method);
    }

    const ifRange = request.headers.get('If-Range');
    if (ifRange) {
      const etag = asset.headers.get('ETag');
      const modified = asset.headers.get('Last-Modified');
      const date = Date.parse(ifRange);
      const matches = ifRange.startsWith('"')
        ? etag && !etag.startsWith('W/') && ifRange === etag
        : modified && Number.isFinite(date) && Date.parse(modified) <= date;
      if (!matches) return withRanges(asset, request.method);
    }

    const match = RANGE.exec(range.trim());
    if (!match) return withRanges(asset, request.method);
    const body = await asset.arrayBuffer();
    const size = body.byteLength;
    let start;
    let end;
    if (match[1] !== '') {
      start = Number(match[1]);
      end = match[2] === '' ? size - 1 : Math.min(Number(match[2]), size - 1);
    } else if (match[2] !== '') {
      start = Math.max(0, size - Number(match[2]));
      end = size - 1;
    }
    if (start === undefined || start > end || start >= size) {
      const headers = new Headers(asset.headers);
      headers.set('Content-Range', `bytes */${size}`);
      headers.delete('Content-Length');
      return new Response(null, {status: 416, headers});
    }
    const headers = new Headers(asset.headers);
    headers.set('Accept-Ranges', 'bytes');
    headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
    headers.set('Content-Length', String(end - start + 1));
    return new Response(body.slice(start, end + 1), {status: 206, headers});
  },
};

function withRanges(response, method) {
  const headers = new Headers(response.headers);
  if (response.ok) headers.set('Accept-Ranges', 'bytes');
  return new Response(method === 'HEAD' ? null : response.body, {status: response.status, headers});
}
