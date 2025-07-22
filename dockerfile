FROM chaoszhu/easynode AS base

RUN apk add --no-cache python3 python3-dev py3-pip git

RUN mkdir -p /easynode/app/logs && \
    mkdir -p /easynode/app/db && \
    chown -R node:node /easynode/app && \
    chmod -R 755 /easynode/app

ENV VIRTUAL_ENV=/easynode/venv
RUN python3 -m venv $VIRTUAL_ENV
ENV PATH="$VIRTUAL_ENV/bin:$PATH"

RUN pip install --no-cache-dir huggingface_hub

USER node
WORKDIR /easynode/app

COPY --chown=node:node sync_data.sh /easynode/app/
RUN chmod +x /easynode/app/sync_data.sh

CMD ["/bin/sh", "-c", "./sync_data.sh & npm run start"]
