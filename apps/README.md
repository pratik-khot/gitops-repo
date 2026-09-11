# Applications

This directory intentionally contains no business workloads yet. Add each workload as `apps/<app-name>/base` with overlays at `apps/<app-name>/overlays/dev`, `staging`, and `prod`.

For App of Apps, add an explicit child Argo CD Application manifest for the workload under the matching overlay and list that child manifest in this Kustomization. Keep the child Application manifest separate from the workload Kustomization to avoid circular references. Keep image tags pinned and cloud credentials outside this repository.
