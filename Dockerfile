FROM alpine:latest

LABEL version="1.0.0"
LABEL repository="http://github.com/taylornielson22/rebase"

RUN apk --no-cache add jq bash curl git git-lfs

ADD entrypoint.sh /entrypoint.sh
RUN chmod +x entrypoint.sh
ENTRYPOINT ["/entrypoint.sh"]
