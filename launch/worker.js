// Runs only for the film (see run_worker_first in wrangler.toml). Static assets on
// Workers ignore Range headers and always answer 200 with the whole file, and Safari
// will not play a video without byte ranges. This serves them; everything else on
// the site is plain static assets with no code in front.

const RANGE = /^bytes=(\d*)-(\d*)$/;

export default {
  async fetch(request, env) {
    const asset = await env.ASSETS.fetch(request.url, { method: 'GET' });
    const header = request.headers.get('Range');
    if (!asset.ok || !header) return withRanges(asset, request.method);

    const match = RANGE.exec(header.trim());
    const body = await asset.arrayBuffer();
    const size = body.byteLength;
    let start;
    let end;
    if (match && match[1] !== '') {
      start = Number(match[1]);
      end = match[2] === '' ? size - 1 : Math.min(Number(match[2]), size - 1);
    } else if (match && match[2] !== '') {
      start = Math.max(0, size - Number(match[2])); // suffix: the last N bytes
      end = size - 1;
    }
    if (start === undefined || start > end || start >= size) {
      const headers = new Headers(asset.headers);
      headers.set('Content-Range', `bytes */${size}`);
      headers.delete('Content-Length');
      return new Response(null, { status: 416, headers });
    }

    const headers = new Headers(asset.headers);
    headers.set('Accept-Ranges', 'bytes');
    headers.set('Content-Range', `bytes ${start}-${end}/${size}`);
    headers.set('Content-Length', String(end - start + 1));
    const slice = request.method === 'HEAD' ? null : body.slice(start, end + 1);
    return new Response(slice, { status: 206, headers });
  },
};

function withRanges(response, method) {
  const headers = new Headers(response.headers);
  if (response.ok) headers.set('Accept-Ranges', 'bytes');
  return new Response(method === 'HEAD' ? null : response.body, { status: response.status, headers });
}
