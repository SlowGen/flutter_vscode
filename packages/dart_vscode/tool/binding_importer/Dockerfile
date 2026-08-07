FROM node:22-bookworm@sha256:5647be709086c696ff32edaaf1c70cd26d1da6ab2b39c32f3c7b4c4a31957e37

WORKDIR /runner

COPY packages/dart_vscode/tool/binding_importer/package.json \
     packages/dart_vscode/tool/binding_importer/package-lock.json ./
RUN npm ci --ignore-scripts

ENV NODE_PATH=/runner/node_modules

WORKDIR /workspace

CMD ["npm", "test", "--prefix", "packages/dart_vscode/tool/binding_importer"]
