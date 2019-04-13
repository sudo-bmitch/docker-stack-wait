FROM docker

COPY docker-stack-wait.sh /

ENTRYPOINT [ "/docker-stack-wait.sh" ]
