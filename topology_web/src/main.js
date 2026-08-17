import { Graph } from '@antv/g6';
import './style.css';
import { loadSnapshot } from './api.js';

const $ = (selector) => document.querySelector(selector);
const state = { graph: null, snapshot: null, aborter: null, summarized: false, selected: null };
const kindName = {
  root: '核心交换机', managed_switch: '管理交换机', unmanaged_switch: '傻瓜交换机',
  device: '网络终端', unknown_device: '未知终端', aggregate: '终端集合',
};

function classify(node) {
  if (node.kind === 'root' || node.kind === 'managed_switch') return 'root';
  if (node.kind === 'unmanaged_switch') return 'unmanaged';
  if (node.kind === 'unknown_device') return 'unknown';
  if (node.kind === 'aggregate') return 'aggregate';
  return /NVR/i.test(`${node.label} ${node.id}`) ? 'nvr' : 'camera';
}

const palette = {
  root: { fill: '#1473e6', stroke: '#75b6ff', shadow: 'rgba(20,115,230,.5)' },
  unmanaged: { fill: '#d97706', stroke: '#fbbf24', shadow: 'rgba(217,119,6,.45)' },
  camera: { fill: '#059669', stroke: '#6ee7b7', shadow: 'rgba(5,150,105,.4)' },
  nvr: { fill: '#7c3aed', stroke: '#c4b5fd', shadow: 'rgba(124,58,237,.4)' },
  unknown: { fill: '#64748b', stroke: '#cbd5e1', shadow: 'rgba(100,116,139,.4)' },
  aggregate: { fill: '#334155', stroke: '#94a3b8', shadow: 'rgba(51,65,85,.4)' },
};

function iconFor(node) {
  return ({ root: '◆', unmanaged: '◇', camera: '●', nvr: '▣', unknown: '?', aggregate: '…' })[classify(node)];
}

function summarize(snapshot) {
  if (snapshot.nodes.length <= 2500 || !state.summarized) return snapshot;
  const byId = new Map(snapshot.nodes.map((node) => [node.id, node]));
  const deviceEdges = new Map();
  const retainedEdges = [];
  for (const edge of snapshot.edges) {
    const child = byId.get(edge.target);
    if (child && classify(child) !== 'root' && ['camera', 'nvr', 'unknown'].includes(classify(child))) {
      const group = deviceEdges.get(edge.source) || [];
      group.push(edge);
      deviceEdges.set(edge.source, group);
    } else retainedEdges.push(edge);
  }
  const hidden = new Set();
  const aggregates = [];
  for (const [parent, edges] of deviceEdges) {
    if (edges.length <= 50) { retainedEdges.push(...edges); continue; }
    edges.forEach((edge) => hidden.add(edge.target));
    const id = `aggregate:${parent}`;
    aggregates.push({ id, kind: 'aggregate', label: `${edges.length} 台终端`, depth: 0,
      metadata_json: JSON.stringify({ count: edges.length, parent }) });
    retainedEdges.push({ id: `${parent}->${id}`, source: parent, target: id, kind: 'aggregate' });
  }
  return {
    ...snapshot,
    nodes: snapshot.nodes.filter((node) => !hidden.has(node.id)).concat(aggregates),
    edges: retainedEdges,
  };
}

function treePositions(snapshot) {
  const children = new Map(snapshot.nodes.map((node) => [node.id, []]));
  const hasParent = new Set();
  for (const edge of snapshot.edges) {
    if (children.has(edge.source) && children.has(edge.target)) {
      children.get(edge.source).push(edge.target);
      hasParent.add(edge.target);
    }
  }
  const roots = snapshot.nodes.filter((node) => !hasParent.has(node.id)).map((node) => node.id);
  const positions = new Map();
  let leaf = 0;
  const visit = (id, depth, visiting = new Set()) => {
    if (positions.has(id) || visiting.has(id)) return positions.get(id)?.x ?? leaf++ * 150;
    visiting.add(id);
    const xs = (children.get(id) || []).map((child) => visit(child, depth + 1, visiting));
    const x = xs.length ? xs.reduce((sum, value) => sum + value, 0) / xs.length : leaf++ * 150;
    positions.set(id, { x, y: depth * 140 });
    visiting.delete(id);
    return x;
  };
  roots.forEach((id) => visit(id, 0));
  snapshot.nodes.forEach((node) => { if (!positions.has(node.id)) visit(node.id, 0); });
  return positions;
}

function graphData(snapshot) {
  const positions = treePositions(snapshot);
  return {
    nodes: snapshot.nodes.map((node) => {
      const category = classify(node);
      const colors = palette[category];
      return {
        id: node.id,
        data: { ...node, category },
        style: {
          ...positions.get(node.id),
          fill: colors.fill, stroke: colors.stroke, lineWidth: 2,
          shadowColor: colors.shadow, shadowBlur: 14,
          labelText: `${iconFor(node)}  ${node.label}`,
          labelFill: '#dce9f8', labelFontSize: 12,
          labelPlacement: 'bottom', labelOffsetY: 8,
        },
      };
    }),
    edges: snapshot.edges.map((edge) => ({
      id: edge.id,
      source: edge.source,
      target: edge.target,
      data: edge,
      style: {
        stroke: '#3d5873', lineWidth: 1.5,
        endArrow: true,
        labelText: edge.port ? `端口 ${edge.port}` : '',
        labelFill: '#8fa8c1', labelFontSize: 10,
        labelBackground: true, labelBackgroundFill: '#0c1928',
        labelBackgroundRadius: 4, labelPadding: [2, 5],
      },
    })),
  };
}

function renderGraph() {
  const view = summarize(state.snapshot);
  document.documentElement.dataset.graphStatus = 'starting';
  state.graph?.destroy();
  state.graph = new Graph({
    container: 'graph',
    autoFit: 'view',
    padding: 56,
    data: graphData(view),
    background: '#08111f',
    layout: { type: 'preset' },
    node: { type: 'rect', style: { size: [96, 42], radius: 9 } },
    edge: { type: 'cubic-vertical' },
    behaviors: ['drag-canvas', 'zoom-canvas', 'drag-element'],
    plugins: [
      { type: 'minimap', size: [180, 110], position: 'bottom-right' },
      { type: 'tooltip', getContent: (_, items) => {
        const item = items?.[0]?.data || items?.[0];
        return `<div class="graph-tooltip"><strong>${item?.label || item?.id || ''}</strong>` +
          `${item?.ip ? `<span>${item.ip}</span>` : ''}${item?.mac ? `<span>${item.mac}</span>` : ''}</div>`;
      } },
    ],
  });
  document.documentElement.dataset.graphStatus = 'constructed';
  state.graph.on('node:click', (event) => showDetails(event.target?.id || event.itemId));
  return state.graph.render().then(() => {
    document.documentElement.dataset.graphStatus = 'rendered';
  }).catch((error) => {
    document.documentElement.dataset.graphStatus = `error:${error.message}`;
    throw error;
  });
}

async function renderWithDeadline(timeoutMs = 8000) {
  let timer;
  try {
    await Promise.race([
      renderGraph(),
      new Promise((resolve) => { timer = setTimeout(() => {
        document.documentElement.dataset.graphStatus += '-timeout';
        resolve();
      }, timeoutMs); }),
    ]);
  } finally { clearTimeout(timer); }
}

function showDetails(id) {
  const node = state.snapshot?.nodes.find((item) => item.id === id);
  if (!node) return;
  state.selected = id;
  const category = classify(node);
  $('#detail-icon').textContent = iconFor(node);
  $('#detail-icon').style.background = palette[category].fill;
  $('#detail-kind').textContent = kindName[node.kind] || node.kind;
  $('#detail-title').textContent = node.label;
  let metadata = {};
  try { metadata = JSON.parse(node.metadata_json || '{}'); } catch { /* keep empty */ }
  const fields = [
    ['节点 ID', node.id], ['IP 地址', node.ip], ['MAC 地址', node.mac],
    ['拓扑深度', node.depth], ['上联端口', metadata.upstream_port],
  ].filter(([, value]) => value !== null && value !== undefined && value !== '');
  $('#detail-fields').innerHTML = fields.map(([name, value]) =>
    `<div><dt>${name}</dt><dd>${String(value)}</dd></div>`).join('');
  $('#detail-panel').hidden = false;
}

function updateDeviceList(query = '') {
  const normalized = query.trim().toLowerCase();
  const results = state.snapshot.nodes.filter((node) =>
    !normalized || `${node.label} ${node.ip || ''} ${node.mac || ''}`.toLowerCase().includes(normalized));
  $('#result-count').textContent = `${results.length}`;
  $('#device-list').innerHTML = results.slice(0, 500).map((node) => {
    const category = classify(node);
    return `<button class="device-row" data-id="${node.id}"><i style="background:${palette[category].fill}">${iconFor(node)}</i>` +
      `<span><strong>${node.label}</strong><small>${node.ip || node.mac || kindName[node.kind] || node.kind}</small></span></button>`;
  }).join('') || '<p class="empty-state">没有匹配的设备</p>';
  document.querySelectorAll('.device-row').forEach((row) => row.addEventListener('click', () => showDetails(row.dataset.id)));
}

function updateStats(snapshot) {
  const switches = snapshot.nodes.filter((node) => ['root', 'managed_switch', 'unmanaged_switch'].includes(node.kind)).length;
  $('#node-count').textContent = snapshot.metadata.node_count.toLocaleString();
  $('#edge-count').textContent = snapshot.metadata.edge_count.toLocaleString();
  $('#switch-count').textContent = switches.toLocaleString();
  $('#device-count').textContent = (snapshot.nodes.length - switches).toLocaleString();
  $('#snapshot-label').textContent = `快照 #${snapshot.metadata.snapshot_id} · ${new Date(snapshot.metadata.created_at * 1000).toLocaleString()}`;
  $('#mode-btn').hidden = snapshot.nodes.length <= 2500;
  $('#mode-btn').textContent = state.summarized ? '显示全部' : '聚合终端';
}

async function refresh() {
  state.aborter?.abort();
  state.aborter = new AbortController();
  $('#error-card').hidden = true;
  $('#loading').hidden = false;
  $('#refresh-btn').disabled = true;
  const progress = { nodes: 0, edges: 0, nodeTotal: 1, edgeTotal: 1 };
  try {
    const started = performance.now();
    const snapshot = await loadSnapshot((kind, loaded, total, metadata) => {
      if (kind === 'metadata') {
        progress.nodeTotal = metadata.node_count || 1;
        progress.edgeTotal = metadata.edge_count || 1;
      } else progress[kind] = loaded;
      const percent = Math.min(100, ((progress.nodes + progress.edges) / (progress.nodeTotal + progress.edgeTotal)) * 100);
      $('#progress-bar').style.width = `${percent}%`;
      $('#loading-detail').textContent = `节点 ${progress.nodes}/${progress.nodeTotal} · 链路 ${progress.edges}/${progress.edgeTotal}`;
    }, state.aborter.signal);
    state.snapshot = snapshot;
    state.summarized = snapshot.nodes.length > 2500;
    updateStats(snapshot);
    updateDeviceList($('#search-input').value);
    await renderWithDeadline();
    $('#snapshot-label').textContent += ` · ${(performance.now() - started).toFixed(0)} ms`;
    $('#loading').hidden = true;
  } catch (error) {
    if (error.name === 'AbortError') return;
    $('#loading').hidden = true;
    $('#error-card').hidden = false;
    $('#error-message').textContent = error.message;
  } finally { $('#refresh-btn').disabled = false; }
}

$('#refresh-btn').addEventListener('click', refresh);
$('#retry-btn').addEventListener('click', refresh);
$('#fit-btn').addEventListener('click', () => state.graph?.fitView({ padding: 56 }));
$('#mode-btn').addEventListener('click', async () => {
  state.summarized = !state.summarized;
  $('#mode-btn').textContent = state.summarized ? '显示全部' : '聚合终端';
  $('#loading').hidden = false;
  await renderWithDeadline();
  $('#loading').hidden = true;
});
$('#search-input').addEventListener('input', (event) => updateDeviceList(event.target.value));
$('#detail-close').addEventListener('click', () => { $('#detail-panel').hidden = true; });
window.addEventListener('resize', () => state.graph?.resize());

refresh();
