# QUERY — 위키 기반 질문 답변

트리거: "어떻게 동작해?", "흐름 설명해줘", "~와 ~의 관계", "~에 대해 정리"

> `$QMD_INDEX` 미선언 시: `QMD_INDEX=$(basename $(pwd))`로 재선언
> 검색 명령 비용·escalation 상세는 `qmd-가이드.md` 참조.

---

## 절차

1. **qmd 검색** — QUERY는 자연어 질문 응답이므로 의미 검색 비중이 높다. 정확 키워드는 `search`, 자연어·개념 질문은 `query --no-rerank`로 시작한다(특히 옵시디언 모드):
   ```bash
   # 정확 키워드·식별자: 위치 파악 (빠름)
   qmd --index "$QMD_INDEX" search "키워드" -c "$QMD_INDEX"

   # 자연어·동의어·개념 질문 (옵시디언 모드는 보통 여기서 시작)
   qmd --index "$QMD_INDEX" query "질문 내용" -c "$QMD_INDEX" --no-rerank

   # rerank가 꼭 필요할 때만 (후보 순서가 애매할 때)
   qmd --index "$QMD_INDEX" query "질문 내용" -c "$QMD_INDEX" -C 5
   ```

2. **wiki Read** (fallback 또는 보강):
   - `docs/wiki/wiki-index.md` 읽기 → 관련 페이지 파악
   - 관련 위키 페이지 읽기

3. **인용 포함 답변** — 출처: 파일 경로 (+ 줄 번호)

4. **가치 있는 답변 → 위키에 환류 제안**:
   ```
   이 답변을 docs/wiki/synthesis/YYYY-MM-DD-주제.md로 저장할까요?
   ```

5. **wiki-log.md 기록**
