ARG DOCKER_VER=stable
FROM docker:${DOCKER_VER}

COPY docker-stack-wait.sh /

ENTRYPOINT [ "/docker-stack-wait.sh" ]
