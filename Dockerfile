ARG DOCKER_VER=19.03.0
FROM docker:${DOCKER_VER}

COPY docker-stack-wait.sh /

ENTRYPOINT [ "/docker-stack-wait.sh" ]
