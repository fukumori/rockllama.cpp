# Patches RKNPU2 para rockllama.cpp

Patches gerados de: https://github.com/invisiofficial/rk-llama.cpp/tree/rknpu2

## Como aplicar manualmente

```bash
git am patches/*.patch
```

## Como regenerar após sync do upstream

```bash
git fetch rknpu2 rknpu2
git format-patch HEAD..rknpu2/rknpu2 --output-directory=patches/ --no-signature
```

## Lista de patches (do mais antigo ao mais novo)

- `0001-RKNPU2-backend-is-implemented.patch`: RKNPU2 backend is implemented
- `0002-.gitignore-is-updated.patch`: .gitignore is updated
- `0003-Implement-Zero-Copy-for-Weights.patch`: Implement Zero-Copy for Weights Pre-pack Weights on
- `0004-Quantization-support-is-implemented.patch`: Quantization support is implemented
- `0005-README.md-is-created.patch`: README.md is created
- `0006-Zero-length-segments-skip-is-added-2.patch`: Zero-length segments skip is added (#2)
- `0007-Hardware-Pipelines-Hybrid-Quantization-are-implement.patch`: Hardware Pipelines & Hybrid Quantization are
- `0008-IOMMU-Domain-Management-is-implemented.patch`: IOMMU Domain Management is implemented
- `0009-Fix-cmake-for-cross-compiling-8.patch`: Fix cmake for cross-compiling (#8)
- `0010-Caching-System-is-fixed.patch`: Caching System is fixed
- `0011-Several-Environment-Variables-for-QoL-are-implemente.patch`: Several Environment Variables for QoL are implemented

---
_Atualizado automaticamente pelo script de sync_
