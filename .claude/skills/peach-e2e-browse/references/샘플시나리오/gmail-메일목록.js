/**
 * Gmail 받은편지함 최근 메일 15개 목록 추출
 *
 * 사전조건:
 *   - Chrome Beta CDP 모드 실행 (./e2e.sh chrome)
 *   - 브라우저에서 Google 계정 로그인 완료
 *
 * 실행: ./e2e.sh run 시나리오/gmail-메일목록.js
 *
 * 선택된 탭에서 실행:
 *   1. www.google.com 이동
 *   2. 상단 Gmail 링크 클릭
 *   3. 받은편지함 메일 목록 추출
 */
const { connect } = require('../lib/connect');

(async () => {
  console.log('🚀 [Gmail 메일목록] 시작');

  const { page } = await connect();

  // 다이얼로그 자동 수락
  const dialogHandler = async (dialog) => {
    console.log(`📢 다이얼로그: ${dialog.message()}`);
    try { await dialog.accept(); } catch (_) {}
  };
  page.on('dialog', dialogHandler);

  try {
    // ── 1. Google 홈으로 이동 ─────────────────────────────────
    console.log('\n📋 [1] www.google.com 이동...');
    await page.goto('https://www.google.com');
    await page.waitForLoadState('domcontentloaded');
    console.log('✅ Google 홈 로딩 완료');

    // ── 2. Gmail 링크 클릭 ────────────────────────────────────
    console.log('\n📋 [2] Gmail 링크 클릭...');

    // Google 상단 네비게이션의 Gmail 링크
    const gmailLink = page.locator('a[href*="mail.google.com"]').first();
    const gmailLinkCount = await gmailLink.count();

    if (gmailLinkCount === 0) {
      // 링크가 없으면 직접 이동
      console.log('   Gmail 링크 없음 — 직접 이동');
      await page.goto('https://mail.google.com/mail/u/0/#inbox');
    } else {
      await gmailLink.click();
    }

    // ── 3. Gmail 로딩 대기 ────────────────────────────────────
    console.log('\n📋 [3] Gmail 받은편지함 로딩 대기...');
    await page.waitForURL('**/mail.google.com/**', { timeout: 15000 });
    await page.waitForSelector('tr.zA', { timeout: 15000 });
    console.log('✅ 메일 목록 로딩 완료');

    // ── 4. 최근 메일 15개 추출 ────────────────────────────────
    console.log('\n📋 [4] 최근 메일 15개 추출...');
    const mails = await page.evaluate(() => {
      const rows = Array.from(document.querySelectorAll('tr.zA')).slice(0, 15);
      return rows.map((tr, i) => {
        const senderEl = tr.querySelector('.yW span');
        const subjectEl = tr.querySelector('.bog');
        const dateEl = tr.querySelector('.xW span');

        const sender = senderEl
          ? (senderEl.getAttribute('name') || senderEl.innerText)
          : '(알 수 없음)';
        const subject = subjectEl ? subjectEl.innerText : '(제목 없음)';
        const date = dateEl
          ? (dateEl.getAttribute('title') || dateEl.innerText)
          : '(날짜 없음)';

        return { no: i + 1, sender, subject, date };
      });
    });
    console.log('✅ 추출 완료');

    // ── 5. 결과 출력 ──────────────────────────────────────────
    console.log('\n📋 [5] 메일 목록 출력');
    console.log('─'.repeat(80));
    console.log(`${'No'.padEnd(4)} ${'발신자'.padEnd(20)} ${'제목'.padEnd(40)} 날짜`);
    console.log('─'.repeat(80));
    for (const m of mails) {
      console.log(
        `${String(m.no).padEnd(4)} ${m.sender.slice(0, 18).padEnd(20)} ${m.subject.slice(0, 38).padEnd(40)} ${m.date}`
      );
    }
    console.log('─'.repeat(80));
    console.log(`총 ${mails.length}건`);

    console.log('\n✨ [Gmail 메일목록] 완료!');

  } catch (e) {
    console.error('\n❌ 에러:', e.message);
    console.log('💡 Chrome Beta에서 Google 계정 로그인이 되어있는지 확인하세요.');
  } finally {
    page.removeListener('dialog', dialogHandler);
    process.exit(0);
  }
})();
