# INGEST — Raw Source → 위키 추가

> 전량 스캔 + 사람 확인 경로. 자동 변경분 경량 처리는 `op-INCREMENTAL.md`를 쓴다.

트리거: "ingest", "wiki에 추가", "문서화해줘", 파일/모듈 언급

> `$QMD_INDEX` 미선언 시: `QMD_INDEX=$(basename $(pwd))`로 재선언

---

## 절차

1. **소스 파악** — `search` 우선, 의미 검색 필요 시 `query --no-rerank` (상세 escalation 기준은 `qmd-가이드.md`):
   ```bash
   qmd --index "$QMD_INDEX" search "모듈명 또는 키워드" -c "$QMD_INDEX"
   # 의미 검색이 꼭 필요할 때만
   qmd --index "$QMD_INDEX" query "질문" -c "$QMD_INDEX" --no-rerank
   # qmd 미사용 시 직접 파일 Read
   ```

2. **요약 확인** — 핵심 3~5줄 요약 후 사람에게 확인

3. **wiki 페이지 생성/업데이트**:
   - code: 모듈 → `entities/module-이름.md`, API → `entities/api-이름.md`, DB → `entities/schema-이름.md`
   - para: 노트 → `sources/YYYY-MM-DD-제목.md`, 인물 → `entities/이름.md`, 프로젝트 → `entities/project-이름.md`
   - 대상 프로젝트에 `docs/기능별설명/`이 있으면 `wiki-경계규칙.md`를 읽고 wiki에 쓸 내용인지 feature-docs 영역인지 먼저 판단한다 (단일 기능 심층 내용은 wiki에 중복 서술하지 않고 링크만)

4. **concepts/ 업데이트** — 아키텍처 패턴, 도메인 개념 반영

5. **related_files 경로 검증** (code 모드):
   - qmd URI와 실제 파일 경로가 다를 수 있음 (하이픈 vs dot 등)
   - related_files에 넣기 전 `ls` 또는 `Glob`으로 실제 존재 확인
   - 존재하지 않는 경로는 제외하거나 정확한 경로로 수정

6. **diagrams/ 생성** (필요 시) — Mermaid로 흐름 시각화

7. **wiki-index.md 갱신** + **wiki-log.md 기록**

8. **qmd 반영** (qmd 설치 시) — 상세 명령·플랫폼 옵션은 `qmd-가이드.md` / `qmd-platform-embedding.md`:
   ```bash
   qmd --index "$QMD_INDEX" update
   qmd --index "$QMD_INDEX" embed --max-docs-per-batch 32 --max-batch-mb 32
   # 정합성 검증 — embed 성공 ≠ 전체 벡터 정합. "differ"가 보이면 embed --force로 마무리
   qmd --index "$QMD_INDEX" doctor | grep -i "vector sample"
   ```
   - 소규모 텍스트 수정: `qmd --index "$QMD_INDEX" update`만
   - 변경 없으면 실행하지 않음

## 페이지 형식

```yaml
---
tags: [wiki, entities|concepts|synthesis|sources|diagrams]
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: [소스 파일 경로]
related_files: [직접 연관된 파일] # code 모드
---

# 제목
> 한 줄 요약

## 핵심 내용
## 연결된 위키 페이지
- [[관련 페이지]]
## 원본 소스
- `경로/파일명`
```
