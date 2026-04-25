#!/bin/bash
# sync-upstream.sh — Sincroniza rockllama.cpp com upstream e reaplica patches rknpu2
set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

echo "=== rockllama.cpp — sync-upstream.sh ==="
echo "Buscando atualizações do upstream (ggml-org/llama.cpp)..."
git fetch upstream

BEHIND=$(git rev-list --count HEAD..upstream/master)
echo "Commits atrás do upstream: $BEHIND"

if [ "$BEHIND" -eq 0 ]; then
  echo "Já estamos sincronizados com o upstream."
  exit 0
fi

echo "Buscando atualizações do rknpu2..."
git fetch rknpu2 rknpu2

BRANCH="sync/$(date +%Y%m%d)"
echo "Criando branch de teste: $BRANCH"
git checkout -b "$BRANCH" upstream/master

echo "Aplicando patches do rknpu2..."
PATCH_ERRORS=0
for patch in patches/*.patch; do
  echo "  Aplicando: $patch"
  if ! git am "$patch"; then
    echo "ERRO: Falha ao aplicar $patch — resolva o conflito manualmente"
    git am --abort
    PATCH_ERRORS=$((PATCH_ERRORS + 1))
    break
  fi
done

if [ "$PATCH_ERRORS" -gt 0 ]; then
  echo ""
  echo "ATENÇÃO: Patches precisam ser atualizados para compatibilidade com a nova versão do upstream."
  echo "Resolva os conflitos e então:"
  echo "  git am --continue"
  echo "  git checkout master && git merge $BRANCH"
  exit 1
fi

echo ""
echo "Todos os patches aplicados com sucesso!"
echo "Faça o merge na main:"
echo "  git checkout master"
echo "  git merge $BRANCH"
echo "  git push origin master"
