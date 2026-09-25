#!/usr/bin/env node
/**
 * selector.js — 탭 선택 + 한글 실시간 검색 선택기
 *
 * 사용법: node selector.js <시나리오_디렉토리> [상태_파일_경로]
 * 출력(stdout): "TAB=<tabIndex>\nSCENARIO=<상대경로>"  또는 빈 줄(취소)
 *
 * 단계:
 *   1. CDP에서 탭 목록을 가져와 ↑↓ 선택
 *   2. 시나리오 목록을 한글 실시간 검색 후 ↑↓ 선택
 */

'use strict';

const fs      = require('fs');
const path    = require('path');
const http    = require('http');
const readline = require('readline');

// ── 인자 ─────────────────────────────────────────────────
const scenariosDir = process.argv[2];
const stateFile    = process.argv[3] || null;

if (!scenariosDir) {
  process.stderr.write('Usage: node selector.js <scenarios_dir> [state_file]\n');
  process.exit(1);
}

const CDP_PORT = process.env.E2E_CDP_PORT || '9333';
const CDP_URL = `http://127.0.0.1:${CDP_PORT}`;

// ── 상태 저장/로드 ────────────────────────────────────────
function loadState() {
  if (!stateFile) return {};
  try { return JSON.parse(fs.readFileSync(stateFile, 'utf8')); }
  catch { return {}; }
}
function saveState(patch) {
  if (!stateFile) return;
  const prev = loadState();
  try {
    fs.writeFileSync(stateFile, JSON.stringify(
      { ...prev, ...patch, updated_at: new Date().toISOString() },
      null, 2
    ), 'utf8');
  } catch {}
}

// ── CDP 탭 목록 가져오기 ──────────────────────────────────
function fetchTabs() {
  return new Promise((resolve) => {
    http.get(`${CDP_URL}/json`, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => {
        try {
          const all = JSON.parse(data);
          const tabs = all
            .filter(t => {
              if (t.type !== 'page') return false;
              if (t.url.startsWith('chrome') || t.url.includes('extension')) return false;
              if (!t.title || !t.title.trim() || t.title.startsWith('http') || t.title.startsWith('&')) return false;
              return true;
            })
            .map(t => ({ id: t.id || '', title: t.title || '', url: t.url || '' }));
          resolve(tabs);
        } catch { resolve([]); }
      });
    }).on('error', () => resolve([]));
  });
}

// ── 시나리오 수집 ─────────────────────────────────────────
function collectScenarios(dir) {
  const results = [];
  function walk(cur) {
    let entries;
    try { entries = fs.readdirSync(cur, { withFileTypes: true }); }
    catch { return; }
    entries.sort((a, b) => a.name.localeCompare(b.name, 'ko'));
    for (const e of entries) {
      const full = path.join(cur, e.name);
      if (e.isDirectory())            walk(full);
      else if (e.name.endsWith('.js')) results.push(path.relative(dir, full));
    }
  }
  walk(dir);
  return results;
}

// ── ANSI 헬퍼 ─────────────────────────────────────────────
const A = {
  up:        n  => `\x1b[${n}A`,
  clearLine:     '\x1b[2K\r',
  cursorShow:    '\x1b[?25h',
  cursorHide:    '\x1b[?25l',
  bold:      s  => `\x1b[1m${s}\x1b[0m`,
  dim:       s  => `\x1b[2m${s}\x1b[0m`,
  cyan:      s  => `\x1b[96m${s}\x1b[0m`,
  yellow:    s  => `\x1b[93m${s}\x1b[0m`,
  green:     s  => `\x1b[92m${s}\x1b[0m`,
  inverse:   s  => `\x1b[7m${s}\x1b[0m`,
  highlight: (text, q) => {
    if (!q) return text;
    const idx = text.toLowerCase().indexOf(q.toLowerCase());
    if (idx < 0) return text;
    return text.slice(0, idx)
      + A.yellow(A.bold(text.slice(idx, idx + q.length)))
      + text.slice(idx + q.length);
  },
};

const SEP = A.cyan('─'.repeat(52));

// ── TTY 설정 ─────────────────────────────────────────────
readline.emitKeypressEvents(process.stdin);
if (process.stdin.isTTY) process.stdin.setRawMode(true);
process.stderr.write(A.cursorHide);

let prevLines = 0;

function cleanup() {
  process.stderr.write(A.cursorShow + '\n');
  if (process.stdin.isTTY) try { process.stdin.setRawMode(false); } catch {}
}
process.on('exit', cleanup);
process.on('SIGINT', () => { cleanup(); process.stdout.write('\n'); process.exit(0); });

// ── 공통 렌더러 ───────────────────────────────────────────
function renderLines(lines) {
  const out = [];
  // 이전 줄 전체를 위로 올라가며 한 줄씩 지움
  if (prevLines > 0) {
    out.push(A.up(prevLines));
    for (let i = 0; i < prevLines; i++) out.push(A.clearLine + '\n');
    out.push(A.up(prevLines));
  }
  // 새 내용 출력
  for (const line of lines) out.push(A.clearLine + line + '\n');
  prevLines = lines.length;
  process.stderr.write(out.join(''));
}

// 단계 전환 시 이전 UI를 완전히 지움
function clearScreen() {
  if (prevLines > 0) {
    const out = [A.up(prevLines)];
    for (let i = 0; i < prevLines; i++) out.push(A.clearLine + '\n');
    out.push(A.up(prevLines));
    process.stderr.write(out.join(''));
  }
  prevLines = 0;
}

// ── 범용 ↑↓ 선택기 ────────────────────────────────────────
// items: [{ label, value }]
// header: 상단 타이틀 문자열
// returns Promise<value | null>
function selectList(items, header) {
  return new Promise((resolve) => {
    if (items.length === 0) { resolve(null); return; }

    const MAX = Math.max(5, (process.stdout.rows || 24) - 6);
    let cursor = 0;
    let scroll = 0;

    function clamp() {
      cursor = Math.max(0, Math.min(cursor, items.length - 1));
      if (cursor < scroll) scroll = cursor;
      if (cursor >= scroll + MAX) scroll = cursor - MAX + 1;
    }

    function draw() {
      const lines = [];
      lines.push(SEP);
      lines.push(A.bold(A.cyan('  ' + header)));
      lines.push(SEP);
      const visible = items.slice(scroll, scroll + MAX);
      for (let i = 0; i < visible.length; i++) {
        const ri = scroll + i;
        const label = visible[i].label;
        if (ri === cursor) lines.push(A.inverse(A.bold(` ▸ ${label} `)));
        else               lines.push(`   ${label}`);
      }
      if (items.length > MAX) {
        lines.push(A.dim(`  ↕ ${scroll + 1}-${Math.min(scroll + MAX, items.length)} / ${items.length}`));
      }
      lines.push(SEP);
      lines.push(A.dim('  [↑↓] 이동  [Enter] 선택  [ESC/Ctrl-C] 취소'));
      renderLines(lines);
    }

    draw();

    function onKey(str, key) {
      if (!key) return;
      if ((key.ctrl && key.name === 'c') || key.name === 'escape') {
        process.stdin.removeListener('keypress', onKey);
        resolve(null);
        return;
      }
      if (key.name === 'return' || key.name === 'enter') {
        process.stdin.removeListener('keypress', onKey);
        resolve(items[cursor].value);
        return;
      }
      if (key.name === 'up')       { cursor--; clamp(); draw(); return; }
      if (key.name === 'down')     { cursor++; clamp(); draw(); return; }
      if (key.name === 'pageup')   { cursor = Math.max(0, cursor - MAX); clamp(); draw(); return; }
      if (key.name === 'pagedown') { cursor = Math.min(items.length - 1, cursor + MAX); clamp(); draw(); return; }
    }

    process.stdin.on('keypress', onKey);
  });
}

// ── 시나리오 실시간 검색 선택기 ───────────────────────────
// returns Promise<string | null>  (상대경로)
function selectScenario(allItems, initQuery, initScenario) {
  return new Promise((resolve) => {
    const MAX = Math.max(5, (process.stdout.rows || 24) - 8);

    let query    = initQuery || '';
    let cursor   = 0;
    let scroll   = 0;
    let filtered = doFilter(query);

    // 마지막 선택 항목으로 커서 복원
    if (initScenario) {
      const idx = filtered.indexOf(initScenario);
      if (idx >= 0) cursor = idx;
    }

    function doFilter(q) {
      if (!q) return [...allItems];
      const lower = q.toLowerCase();
      return allItems.filter(s => s.toLowerCase().includes(lower));
    }

    function clamp() {
      if (!filtered.length) { cursor = 0; scroll = 0; return; }
      cursor = Math.max(0, Math.min(cursor, filtered.length - 1));
      if (cursor < scroll) scroll = cursor;
      if (cursor >= scroll + MAX) scroll = cursor - MAX + 1;
    }

    function draw() {
      const lines = [];
      lines.push(SEP);

      // 검색 입력란
      lines.push(A.bold(A.cyan('🔍 검색> ')) + query + '█');

      // 매칭 카운트
      const cnt = filtered.length === allItems.length
        ? A.dim(`  전체 ${allItems.length}개`)
        : A.dim(`  ${filtered.length} / ${allItems.length}개 매칭`);
      lines.push(cnt);
      lines.push(SEP);

      // 목록
      if (!filtered.length) {
        lines.push(A.dim('  (매칭 없음)'));
      } else {
        const visible = filtered.slice(scroll, scroll + MAX);
        for (let i = 0; i < visible.length; i++) {
          const ri    = scroll + i;
          const item  = visible[i];
          const label = A.highlight(item, query);
          if (ri === cursor) lines.push(A.inverse(A.bold(` ▸ ${label} `)));
          else               lines.push(`   ${label}`);
        }
        if (filtered.length > MAX) {
          lines.push(A.dim(`  ↕ ${scroll + 1}-${Math.min(scroll + MAX, filtered.length)} / ${filtered.length}`));
        }
      }

      lines.push(SEP);
      lines.push(A.dim('  [↑↓] 이동  [Enter] 실행  [Ctrl-U] 검색어 초기화  [ESC] 취소'));
      renderLines(lines);
    }

    draw();

    function onKey(str, key) {
      // 한글/일반 문자 (key 없이 str만 오는 경우 포함)
      if (!key) {
        if (str) { query += str; filtered = doFilter(query); cursor = 0; scroll = 0; }
        draw(); return;
      }

      if ((key.ctrl && key.name === 'c') || key.name === 'escape') {
        process.stdin.removeListener('keypress', onKey);
        resolve(null); return;
      }
      if (key.name === 'return' || key.name === 'enter') {
        process.stdin.removeListener('keypress', onKey);
        resolve(filtered[cursor] || null); return;
      }
      if (key.name === 'up')       { cursor--; clamp(); draw(); return; }
      if (key.name === 'down')     { cursor++; clamp(); draw(); return; }
      if (key.name === 'pageup')   { cursor = Math.max(0, cursor - MAX); clamp(); draw(); return; }
      if (key.name === 'pagedown') { cursor = Math.min(filtered.length - 1, cursor + MAX); clamp(); draw(); return; }
      if (key.name === 'backspace') {
        if (query.length) { query = [...query].slice(0, -1).join(''); filtered = doFilter(query); cursor = 0; scroll = 0; }
        draw(); return;
      }
      if (key.ctrl && key.name === 'u') {
        query = ''; filtered = doFilter(query); cursor = 0; scroll = 0;
        draw(); return;
      }
      if (str && !key.ctrl && !key.meta) {
        query += str; filtered = doFilter(query); cursor = 0; scroll = 0;
        draw(); return;
      }
      draw();
    }

    process.stdin.on('keypress', onKey);
  });
}

// ── 메인 흐름 ─────────────────────────────────────────────
(async () => {
  const state     = loadState();
  const allItems  = collectScenarios(scenariosDir);

  // ── STEP 1: 탭 선택 ──────────────────────────────────────
  const tabs = await fetchTabs();

  let selectedTab = null;

  if (tabs.length === 0) {
    // CDP 미연결 또는 탭 없음 → 탭 선택 생략
    process.stderr.write(A.dim('  (CDP 탭 없음 — URL 패턴 자동 탐지)\n'));
    prevLines = 1;
    clearScreen();
  } else {
    // 마지막 탭 id로 커서 복원
    let initTabIdx = 0;
    if (state.last_tab_id) {
      const found = tabs.findIndex(t => t.id === state.last_tab_id);
      if (found >= 0) initTabIdx = found;
    }

    const tabItems = tabs.map((t, i) => ({
      title: `${A.dim('[' + i + ']')} ${t.title.slice(0, 60)}`,
      url:   A.dim('  ' + t.url.slice(0, 70)),
      value: t.id,
    }));

    selectedTab = await (function selectTabList(items, header, initCursor) {
      return new Promise((resolve) => {
        // 탭 1개당 2줄(title + url) — MAX는 탭 개수 기준
        const MAX = Math.max(3, Math.floor(((process.stdout.rows || 24) - 6) / 2));
        let cursor = Math.max(0, Math.min(initCursor || 0, items.length - 1));
        let scroll = 0;

        function clamp() {
          cursor = Math.max(0, Math.min(cursor, items.length - 1));
          if (cursor < scroll) scroll = cursor;
          if (cursor >= scroll + MAX) scroll = cursor - MAX + 1;
        }
        clamp();

        function draw() {
          const lines = [];
          lines.push(SEP);
          lines.push(A.bold(A.cyan('  ' + header)));
          lines.push(SEP);
          const visible = items.slice(scroll, scroll + MAX);
          for (let i = 0; i < visible.length; i++) {
            const ri = scroll + i;
            const t  = items[ri];
            if (ri === cursor) {
              lines.push(A.inverse(A.bold(` ▸ ${t.title} `)));
              lines.push(A.inverse(`    ${t.url} `));
            } else {
              lines.push(`   ${t.title}`);
              lines.push(`  ${t.url}`);
            }
          }
          if (items.length > MAX)
            lines.push(A.dim(`  ↕ ${scroll + 1}-${Math.min(scroll + MAX, items.length)} / ${items.length}`));
          lines.push(SEP);
          lines.push(A.dim('  [↑↓] 이동  [Enter] 선택  [ESC/Ctrl-C] 취소'));
          renderLines(lines);
        }

        draw();

        function onKey(str, key) {
          if (!key) return;
          if ((key.ctrl && key.name === 'c') || key.name === 'escape') {
            process.stdin.removeListener('keypress', onKey);
            resolve(null); return;
          }
          if (key.name === 'return' || key.name === 'enter') {
            process.stdin.removeListener('keypress', onKey);
            resolve(items[cursor].value); return;
          }
          if (key.name === 'up')       { cursor--; clamp(); draw(); return; }
          if (key.name === 'down')     { cursor++; clamp(); draw(); return; }
          if (key.name === 'pageup')   { cursor = Math.max(0, cursor - MAX); clamp(); draw(); return; }
          if (key.name === 'pagedown') { cursor = Math.min(items.length - 1, cursor + MAX); clamp(); draw(); return; }
        }
        process.stdin.on('keypress', onKey);
      });
    })(tabItems, `탭 선택  (${tabs.length}개)`, initTabIdx);

    if (selectedTab === null) {
      cleanup(); process.stdout.write('\n'); process.exit(0);
    }
    clearScreen();  // 탭 UI 완전히 지우고 시나리오 UI 시작
  }

  // ── STEP 2: 시나리오 검색 선택 ───────────────────────────
  if (allItems.length === 0) {
    process.stderr.write('📭 시나리오가 없습니다.\n');
    process.stdout.write('\n');
    process.exit(0);
  }

  const selectedScenario = await selectScenario(
    allItems,
    state.last_query    || '',
    state.last_scenario || ''
  );

  if (!selectedScenario) {
    cleanup(); process.stdout.write('\n'); process.exit(0);
  }

  // 상태 저장
  saveState({
    last_tab_id:    selectedTab,
    last_scenario:  selectedScenario,
    last_query:     '', // 검색어는 매번 새로 입력하는 게 자연스러움
  });

  // 결과 출력 (bash가 파싱)
  const tabLine = selectedTab ? `TAB_ID=${selectedTab}\n` : '';
  process.stdout.write(`${tabLine}SCENARIO=${selectedScenario}\n`);
  process.exit(0);
})();
