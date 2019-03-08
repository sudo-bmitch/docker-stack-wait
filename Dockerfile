FROM docker

ADD docker-stack-wait.sh /

ENTRYPOINT [ "/docker-stack-wait.sh" ]
