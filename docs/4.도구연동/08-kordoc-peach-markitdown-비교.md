# kordoc와 peach-markitdown 비교

검증일: 2026-07-06

## 결론

HWP 5.x 문서를 Markdown으로 변환해야 한다면 `kordoc`가 우선 선택이다. 실제 HWP 5.x 내부 업무 문서 1건을 변환했을 때 `kordoc@3.17.0`은 성공했고, `peach-markitdown`은 내부적으로 `markitdown`에 위임된 뒤 HWP 비지원 오류로 실패했다.

`kordoc`는 HWPX 전용 도구가 아니다. 공식 지원 범위는 HWP 3.x, HWP 5.x, HWPX, HWPML, PDF, XLS, XLSX, DOCX의 Markdown 변환이다. 다만 구형 Word `.doc`는 공식 지원 범위로 확인하지 못했으므로 `DOCX`와 구분해서 말해야 한다.

또한 `kordoc`가 `peach-markitdown`을 전면 대체하는 관계도 아니다. `peach-markitdown`은 PDF, PPTX, DOCX, XLSX, HTML, CSV, JSON, XML, ZIP, EPUB, 이미지처럼 범용 문서 변환과 폴더 일괄 변환 로그 체계에 강점이 있다. 반대로 `kordoc`는 HWP, HWPX, HWPML, PDF 표 복원, 양식 채우기, 문서 비교, Markdown에서 HWPX 생성 같은 한국 문서 처리에 특화되어 있다.

권장 라우팅은 다음과 같다.

| 입력/목적 | 권장 도구 | 이유 |
| --- | --- | --- |
| `.hwp` / HWP 5.x | `kordoc` | 실제 검증에서 성공. `markitdown`은 HWP 비지원 |
| `.hwp3` / 구버전 HWP | `kordoc` | kordoc 공식 지원 범위 |
| `.hwpx` | 목적별 선택 | 단순 추출은 기존 `peach-markitdown`도 가능. 표, 양식, 비교, 패치, HWPX 재생성은 `kordoc` 우선 |
| PDF 관공서 표 문서 | `kordoc` 우선 검토 | 표 복원과 한국 행정문서 구조 처리에 초점 |
| 일반 PDF | 목적별 선택 | 표/공문서 구조가 중요하면 `kordoc`, 범용 일괄 처리와 로그가 중요하면 `peach-markitdown` |
| DOCX | 목적별 선택 | 둘 다 후보. 한국 공문서/표/연동 기능은 `kordoc`, 범용 일괄 처리 흐름은 `peach-markitdown` |
| 구형 Word `.doc` | 별도 검증 필요 | `kordoc` 공식 표기는 `DOCX`이며 `.doc` 지원은 확인 필요 |
| PPTX/HTML/CSV/JSON/XML/ZIP/EPUB/이미지 일괄 변환 | `peach-markitdown` | `kordoc` 공식 범위 밖이거나 기존 스킬의 요약 JSON, 실패 로그 흐름이 더 적합 |
| Markdown -> HWPX, 양식 채우기, 문서 비교 | `kordoc` | `generate`, `fill`, `patch`, `compare` 계열 기능 제공 |

## kordoc 설치와 실행

사전 조건은 Node.js 18 이상이다. 이번 검증 환경은 Node `v24.16.0`, npm `11.13.0`이었다.

AI 클라이언트 MCP 연동까지 한 번에 설정하려면 아래 명령을 사용한다.

```bash
npx -y kordoc setup
```

CLI 변환만 필요하면 별도 설치 없이 `npx`로 바로 실행한다.

```bash
npx -y kordoc@latest input.hwp -o output.md
npx -y kordoc@latest input.hwpx -o output.md
npx -y kordoc@latest input.pdf -o output.md
npx -y kordoc@latest input.docx -o output.md
npx -y kordoc@latest *.pdf -d ./converted
```

수동 MCP 등록이 필요한 환경에서는 아래 형태를 쓴다.

```json
{
  "mcpServers": {
    "kordoc": {
      "command": "npx",
      "args": ["-y", "kordoc", "mcp"]
    }
  }
}
```

Windows에서 MCP 클라이언트가 `.cmd`를 찾지 못하면 `cmd /c npx` 래핑을 사용한다.

```json
{
  "mcpServers": {
    "kordoc": {
      "command": "cmd",
      "args": ["/c", "npx", "-y", "kordoc", "mcp"]
    }
  }
}
```

Claude Code 플러그인 방식으로 쓰려면 다음 명령을 사용한다.

```text
/plugin marketplace add chrisryugj/kordoc
/plugin install kordoc@kordoc
```

과거 글로벌 설치가 깨져 `MODULE_NOT_FOUND`가 나오면 글로벌 설치를 지운 뒤 최신 버전으로 다시 실행한다.

```bash
npm uninstall -g kordoc
npx -y kordoc@latest setup
```

## 실제 변환 검증

검증 대상은 HWP 5.x 형식의 내부 업무 문서 1건이다. 공개 가능한 문서 저장소 원칙상 원문 제목, 고객명, 본문 내용, 로컬 경로는 이 문서에 기록하지 않는다.

### kordoc

실행 명령:

```bash
npx -y kordoc@latest input.hwp -o output.md
```

결과:

- 사용 버전: `kordoc@3.17.0`
- 변환 상태: 성공
- 출력 형식: Markdown
- 산출물 규모: 64줄, 3,176바이트
- 확인한 품질: 섹션 번호, 본문 문단, 예시 항목, 안내 문구가 읽을 수 있는 Markdown으로 추출됨
- 특이점: 샘플 문서에는 복잡한 표가 없어 표 복원 품질은 별도 표 문서로 추가 검증 필요

### peach-markitdown

실행 명령:

```bash
python3 /path/to/peach-markitdown/scripts/convert_one.py \
  --source input.hwp \
  --output output.md
```

결과:

- 변환 상태: 실패
- 실패 지점: `.hwp`는 `peach-markitdown`의 별도 처리 대상이 아니므로 `markitdown`에 위임됨
- 오류 성격: `markitdown`이 HWP를 지원하지 않아 `UnsupportedFormatException` 발생
- 추가 관찰: 임시 환경에서 bootstrap 실행 시 Python 3.9.6 때문에 `python-hwpx` 설치가 실패했다. `python-hwpx`는 Python 3.10 이상이 필요하다. 이 문제는 HWP 실패의 직접 원인은 아니지만, HWPX 경로를 안정화하려면 Python 3.10 이상 환경이 필요하다.

## 추가 성능/품질 측정

추가로 PDF, PPTX, DOCX 샘플 3건을 같은 장비에서 측정했다. 공개 가능한 문서 저장소 원칙상 원본 파일명, 고객명, 로컬 경로는 기록하지 않는다.

측정 기준:

- 측정일: 2026-07-06
- `kordoc`: `3.17.0`
- `markitdown`: `0.1.5`
- 시간 기준: 설치/bootstrap 시간을 제외한 변환 명령 1회 실행 시간(`/usr/bin/time -p real`)
- 산출물 기준: 변환 직후 줄 수/파일 크기 확인 후 `.md` 산출물 삭제

| 샘플 | 도구 | 결과 | 시간 | 산출물 | 품질 메모 |
| --- | --- | --- | ---: | --- | --- |
| PDF 견적서 1페이지 | `kordoc` | 성공 | 최초 8.56초, 재실행 1.34초 | 23줄 / 4.5KB | HTML `<table>` 중심으로 표 구조 보존. 최초 실행은 `npx` 준비 비용 영향이 큼 |
| PDF 견적서 1페이지 | `peach-markitdown` | 성공 | 최초 0.98초, 재실행 1.11초 | 45줄 / 6.4KB | Markdown 표와 일반 텍스트로 추출. 일부 숫자/셀 간격이 깨질 수 있음 |
| PPTX 피드백 문서 | `kordoc` | 실패 | 0.58초 | 없음 | PPTX는 공식 지원 범위 밖이며 ZIP 기반 파일을 HWPX처럼 해석하다 실패 |
| PPTX 피드백 문서 | `peach-markitdown` | 성공 | 0.93초 | 45줄 / 1.1KB | 슬라이드 번호, 텍스트, 이미지 참조가 추출됨 |
| DOCX 사진 문서 | `kordoc` | 부분 성공 | 0.72초 | MD 0B, 이미지 1개 | 본문 텍스트는 없고 이미지 파일은 별도 추출됨 |
| DOCX 사진 문서 | `peach-markitdown` | 부분 성공 | 0.85초 | 160B | 이미지 자체보다는 이미지 설명 alt 문구가 남음 |

이번 추가 측정의 판단:

- PDF 표 문서는 `kordoc`가 구조 보존 면에서 유리했다. 다만 `npx` 최초 실행 시간은 별도 감안해야 한다.
- PPTX는 `peach-markitdown`이 명확히 적합하다. `kordoc` 공식 지원 범위가 아니다.
- 이미지 중심 DOCX는 목적에 따라 다르다. 원본 이미지 추출이 중요하면 `kordoc`, LLM 입력용 짧은 이미지 설명이 필요하면 `peach-markitdown` 결과가 더 유용할 수 있다.
- 성능/품질 측정 후 변환된 `.md` 산출물은 삭제하고, 측정값과 판단만 문서에 남긴다.

## 도구별 강점

### kordoc

- HWP 3.x, HWP 5.x, HWPX, HWPML, PDF, XLS, XLSX, DOCX를 Markdown으로 변환할 수 있다.
- 설치 없이 `npx -y kordoc@latest`로 단건 CLI 실행이 가능하다.
- MCP 서버, Claude Code 플러그인, CLI를 모두 제공한다.
- Markdown 추출 외에 문서 비교, 양식 채우기, 원본 서식 보존 패치, Markdown에서 HWPX 생성, SVG 렌더링 같은 한국 공문서 중심 기능이 있다.
- HWP 원본을 한컴오피스 없이 macOS/Linux에서도 처리할 수 있다는 점이 실무상 크다.

### peach-markitdown

- 기존 PeachSolution 스킬 체계에 맞춰 bootstrap, 단일 파일 변환, 폴더 일괄 변환, 실패 로그를 제공한다.
- PDF, PPTX, DOCX, XLSX, HTML, CSV, JSON, XML, ZIP, EPUB, 이미지 등 일반 문서 묶음 변환에 적합하다.
- HWPX는 `python-hwpx` 기반 별도 추출기로 처리한다.
- 현재 스킬 범위가 명확하고, 실패 파일을 로그로 남기는 운영 흐름이 좋다.

## 전체 평가

`peach-markitdown`이 `kordoc`보다 전체적으로 못하다고 보기는 어렵다. 두 도구의 중심이 다르다.

`kordoc`는 HWP/HWPX/PDF/DOCX/XLSX처럼 한국 업무 문서에서 자주 만나는 파일을 LLM 입력으로 바꾸는 데 강하다. 특히 HWP 5.x, HWPX 양식, 관공서 PDF 표, 문서 비교, HWPX 생성/패치 같은 작업은 `peach-markitdown`보다 목적 적합성이 높다.

`peach-markitdown`은 범용 변환 스킬이다. 여러 포맷이 섞인 폴더를 일괄 변환하고, 성공/실패 요약과 오류 로그를 남기는 운영 흐름이 강점이다. HWP 계열을 제외한 일반 문서 묶음 처리에서는 계속 유효하다.

따라서 실무 판단은 “어느 도구가 더 우수한가”가 아니라 “입력 파일과 목적에 따라 라우팅한다”가 맞다.

## 리스크와 주의점

`kordoc`는 빠르게 발전 중인 npm 패키지다. `@latest`는 편하지만, 운영 자동화에 넣을 때는 버전을 고정하는 편이 재현성이 좋다.

```bash
npx -y kordoc@3.17.0 input.hwp -o output.md
```

또한 `kordoc` 보안 문서는 이 도구가 샌드박스가 아니라 Node.js 런타임과 의존성을 신뢰하는 문서 파서라고 설명한다. 외부에서 받은 문서를 대량 처리할 때는 격리된 작업 디렉터리나 컨테이너에서 실행하는 편이 안전하다.

`peach-markitdown`은 HWP를 지원하지 않는다. HWP가 들어올 수 있는 업무에서는 실패 후 사람이 다시 처리하는 흐름이 생기므로, 확장자 라우팅을 명시적으로 추가하는 것이 좋다.

## 권장 개선안

`peach-markitdown` 스킬을 유지하되, HWP 계열만 `kordoc`로 라우팅하는 방식이 가장 실용적이다.

1. `.hwp`, `.hwp3`, `.hwpml`은 `kordoc`로 변환한다.
2. `.hwpx`는 기본 `python-hwpx` 경로를 유지하되, 표/양식/패치/생성 목적이면 `kordoc`를 선택한다.
3. 나머지 범용 문서는 기존처럼 `markitdown`을 사용한다.
4. 일괄 변환 스크립트는 성공/실패 요약 JSON과 오류 로그 형식을 유지한다.
5. 운영 자동화에서는 `kordoc@latest` 대신 검증된 버전을 고정한다.

## 참고 자료

- GitHub: `https://github.com/chrisryugj/kordoc`
- npm: `https://www.npmjs.com/package/kordoc`
- MarkItDown: `https://github.com/microsoft/markitdown`
