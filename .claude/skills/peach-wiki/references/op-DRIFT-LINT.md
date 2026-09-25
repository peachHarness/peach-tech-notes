# DRIFT / LINT — 변경 감지·정합성 점검

> `$QMD_INDEX` 미선언 시: `QMD_INDEX=$(basename $(pwd))`로 재선언

---

## DRIFT — git 변경 감지 후 위키 갱신

트리거: "wiki 업데이트해줘", "변경사항 반영해줘"
**code 모드(.git 존재)에서만 활성화.**

### 절차

1. **변경 파일 목록 추출**:
   ```bash
   git diff --name-only HEAD~1    # 마지막 커밋
   git diff --name-only           # 미커밋 변경
   ```

2. **영향받은 위키 페이지 파악** — 변경 파일의 `related_files`를 가진 위키 페이지 검색

3. **위키 페이지 업데이트** — 변경 내용 반영, `updated` 날짜 갱신

4. **qmd 반영** (qmd 설치 시):
   ```bash
   qmd --index "$QMD_INDEX" update
   ```

5. **새 모듈 감지** → 자동 INGEST 제안

6. **wiki-log.md 기록**

---

## LINT — 위키 점검

트리거: "wiki 점검", "lint", "문서 정합성 확인"

### 점검 항목

1. **드리프트 탐지** (code 모드): git log vs wiki updated 날짜 비교
2. **고아 페이지**: wiki-index.md에 없는 페이지
3. **깨진 소스 링크**: 삭제된 파일 참조 여부
4. **모순**: 같은 주제에 대해 다른 설명
5. **미문서화 항목**: 소스에는 있는데 위키 페이지 없는 것
6. **템플릿 드리프트**: WIKI-AGENTS.md가 최신 템플릿과 차이 여부

### 리포트 형식
```
## [YYYY-MM-DD] lint | [프로젝트명]
- 드리프트 위험: N개 페이지
- 고아 페이지: N개
- 깨진 링크: N개
- 미문서화: [목록]
- 권고: [조치 목록]
```
