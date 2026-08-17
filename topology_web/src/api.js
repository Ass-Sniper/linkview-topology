const API_PATH = '/cgi-bin/topology';

async function fetchJson(params, signal) {
  const response = await fetch(`${API_PATH}?${new URLSearchParams(params)}`, {
    signal,
    headers: { Accept: 'application/json' },
    cache: 'no-store',
  });
  if (!response.ok) throw new Error(`API ${response.status}: ${await response.text()}`);
  return response.json();
}

async function loadCollection(kind, metadata, onProgress, signal) {
  const expected = kind === 'nodes' ? metadata.node_count : metadata.edge_count;
  const items = [];
  let cursor = 0;
  do {
    const page = await fetchJson({
      action: kind,
      snapshot_id: metadata.snapshot_id,
      cursor,
      limit: 1000,
    }, signal);
    if (page.version !== metadata.version) throw new Error('快照版本在加载期间发生变化');
    items.push(...page.items);
    cursor = page.next_cursor;
    onProgress(kind, items.length, expected);
  } while (cursor !== null);
  return items;
}

export async function loadSnapshot(onProgress, signal) {
  const metadata = await fetchJson({ action: 'metadata' }, signal);
  onProgress('metadata', 1, 1, metadata);
  const [nodes, edges] = await Promise.all([
    loadCollection('nodes', metadata, onProgress, signal),
    loadCollection('edges', metadata, onProgress, signal),
  ]);
  return { metadata, nodes, edges };
}
