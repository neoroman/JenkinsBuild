# test

`config.json`은 **로컬·테스트용 샘플(픽스처)** 일 뿐이며, 운영 환경의 실제 비밀번호·토큰·내부 URL을 반영한 설정 파일이 아닙니다. CI나 수동 실행에서 이 경로를 쓸 때도 **실비밀을 넣어 커밋하지 말 것**.

## 최상위 키 델타 (AngelNet-DistSite `config.json` 대비)

사이트 쪽 설정과 테스트 픽스처의 **스키마 형태(최상위 키)** 가 어긋나지 않는지, 분기·주요 변경 후에 한 번씩 맞출 것. 값이나 하위 키는 여기서 다루지 않음.

- **제외**: `mail-gmail` — 백업용·미사용 블록으로 **델타 점검에서 제외**한다.
- **점검 명령** (저장소 루트를 `JenkinsBuild` 로 둘 때; `jq` 필요):

```bash
SITE_JSON="../AngelNet-DistSite/config/config.json"
TEST_JSON="test/config.json"
diff <(jq -r 'keys[] | select(. != "mail-gmail")' "$SITE_JSON" | sort) \
     <(jq -r 'keys[]' "$TEST_JSON" | sort) && echo "OK: no top-level key delta (mail-gmail excluded)"
```

차이가 없으면 `diff`가 아무 것도 출력하지 않고 종료 코드 0이다.

- **기준선 (2026-04-07)**: 위 기준에서 **추가·삭제되는 최상위 키 없음**. DistSite에만 있는 최상위 키는 `mail-gmail` 뿐이며, 이는 점검에서 제외한다.
