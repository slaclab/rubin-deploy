# rubin-deploy

Notes and guides for deploying Rubin Science Platform (RSP) at USDF (SLAC) using `phalanx`.

### Requirements
The following are binary and authentication requirements prior to beginning an RSP deployment with `phalanx`.

Binaries:
- kubectl (for general Kubernetes admin)
- yq or jq (for reading/processing YAML files (e.g., Helm Chart values))
- vault (for Vault RSP authentication management)
- helm (For Helm Kubernetes package management)
- argocd (for general ArgoCD admin)

Vault:
- Set VAULT_ADDR environment variable so that `vault` commands default to that instance:
  ```
  $ export VAULT_ADDR=https://vault.slac.stanford.edu
  ```
- Pre-populate Vault secrets:
  * Docker images
  ```
  $ vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/pull-secret .dockerconfigjson='{}'
  $ vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/pull-secret password=arghargh
  ```
  * Nublado2 (Vera C. Rubin Observatory instantiation of JupyterHub on Kubernetes)
  ```
  vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/nublado2 proxy_token=$(openssl rand -hex 32) crypto_key=$(openssl rand -hex 32)
  ```
- approle (used instead of tokens for persistence)
  * To create approle (assumes policy has been installed on Vault server):
    ```
      $ vault auth enable approle
      $ vault write auth/approle/role/rubin-data-dev.slac.stanford.edu \
      secret_id_ttl=10m \
      token_num_uses=10 \
      token_ttl=20m \
      token_max_ttl=30m \
      secret_id_num_uses=40 \
      policies=rubin
    ```
- ArgoCD admin (choose <ARGO_ADMIN_PASSWORD>):
  ```
  vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/installer argocd.admin.plaintext_password=<ARGO_ADMIN_PASSWORD>
  ```


Generate passwords
---

0. pip3 install --upgrade --user pip
1. pip3 install --user bcrypt cryptography pyyaml onepassword
2. run generate
  ```
  ❯ ./generate_secrets.py usdfdev
[pull-secret .dockerconfigjson] (.docker/config.json to pull images)
Current contents:

New filename with contents (empty to not change):
[butler-secret aws-credentials.ini] (AWS credentials for butler)
Current contents:

New filename with contents (empty to not change):
[butler-secret postgres-credentials.txt] (Postgres credentials for butler)
Current contents:

New filename with contents (empty to not change):
[tap slack_webhook_url] (slack webhook url for querymonkey): [current: ]
[tap google_creds.json] (file containing google service account credentials)
Current contents:

New filename with contents (empty to not change):
[mobu ALERT_HOOK] (Slack webhook for reporting mobu alerts.  Or use None for no alerting.): [current: ]
[gafaelfawr cloudsql] (Use CloudSQL? (y/n):): [current: ] n
[gafaelfawr auth_type] (Use cilogon or github?): [current: ] github
[gafaelfawr github-client-secret] (GitHub client secret): [current: ]
[installer argocd.admin.plaintext_password] (Admin password for ArgoCD?): [current: ] rubin1
[argocd dex.clientSecret] (OAuth client secret for ArgoCD (either GitHub or Google)?): [current: ] GitHub
[cert-manager enabled] (Use cert-manager? (y/n):): [current: ] n
[ingress-nginx tls.key] (Certificate private key)
Current contents:

New filename with contents (empty to not change):
[ingress-nginx tls.crt] (Certificate chain)
Current contents:

New filename with contents (empty to not change):
```

This will generate files under the `secrets` folder.


2. export VAULT_PATH=secret/rubin/rubin-data-dev.slac.stanford.edu

3. ./write_secrets.sh usdfdev


---
### Deployment
1. Fork `phalanx` from https://github.com/lsst-sqre/phalanx
2. If using GitOps, create feature branch (e.g., `slac-initial-deploy`):
  ```
  $ git checkout -b slac-initial-deploy
  ```
3. Add/modify science-platform/values-usdfdev.yaml for site:
  * Site-specific (usdfdev) settings:
  ```
  environment: usdfdev
  fqdn: rubin-data-dev.slac.stanford.edu
  vault_path_prefix: secret/rubin/rubin-data-dev.slac.stanford.edu
  ```
  * Disable services:
    * `cert-issuer`
    ```
      cert-issuer:
        enabled: false
    ```
    * `cert-manager` (all traffic goes through F5's)
    ```
      cert-manager:
        enabled: false
    ```  
    * `gafaelfawr`
    ```
      gafaelfawr:
        enabled=false
    ```
    * `ingress_nginx`
    ```
      ingress_nginx:
        enabled: false
    ```
    * `ancher_external_ip_webhook`
    ```
      rancher_external_ip_webhook:
        enabled=false
    ```
    * `tap:`
    ```
      tap:
        enabled=false
    ```
4. Modify install script `installer/install.sh`:
  * Set to use Vault approle secret_id instead of token, which won't expire:
  ```
  [...]
  export VAULT_SECRET_ID=${2:?$USAGE}
  [...]
  echo "Set VAULT_TOKEN in a secret for vault-secrets-operator..."
  # The namespace may not exist already, but don't error if it does.
  kubectl create ns vault-secrets-operator || true
  kubectl create secret generic vault-secrets-operator \
    --namespace vault-secrets-operator \
    --from-literal=VAULT_ROLE_ID=$(vault read --format=json auth/approle/role/rubin-data-dev.slac.stanford.edu/role-id | jq -M .data.role_id  | sed 's/"//g') \
    --from-literal=VAULT_SECRET_ID=${VAULT_SECRET_ID} \
    --from-literal=VAULT_TOKEN_MAX_TTL=600 \
    --dry-run=client -o yaml | kubectl apply -f -  
  ```
  * Comment out ArgoCD syncing of disabled services (see above):
  ```
  #argocd app sync ingress-nginx \
  #  --port-forward \
  #  --port-forward-namespace argocd
  [...]
  ```
5. Copy IDF Dev values files (`services/values-idfdev.yaml`) and modify for USDF Dev site-specific configuration (e.g., create `services/values-usdfdev.yaml` under the following services with a corresponding IDF Dev values file):
  * services/argocd/values-usdfdev.yaml
  * services/cert-issuer/values-usdfdev.yaml
  * services/cert-manager/values-usdfdev.yaml
  * services/gafaelfawr/values-usdfdev.yaml
  * services/ingress-nginx/values-usdfdev.yaml
  * services/landing-page/values-usdfdev.yaml
  * services/mobu/values-usdfdev.yaml
  * services/moneypenny/values-usdfdev.yaml
  * services/nublado/values-usdfdev.yaml
  * services/nublado2/values-usdfdev.yaml
  * services/obstap/values-usdfdev.yaml
  * services/portal/values-usdfdev.yaml
  * services/postgres/values-usdfdev.yaml
  * services/rancher-external-ip-webhook/values-usdfdev.yaml
  * services/squareone/values-usdfdev.yaml
  * services/tap/values-usdfdev.yaml
  * services/vault-secrets-operator/values-usdfdev.yaml
  * services/wf/values-usdfdev.yaml

6. Authenticate with Kubernetes via OIDC Heptio Gangway: https://k8s-master-login.slac.stanford.edu
7. Log in as Vault approle using Vault `role_id` and `secret_id`:
  * Get the Vault approle `role_id`:
    ```
    $ vault read auth/approle/role/rubin-data-dev.slac.stanford.edu/role-id
    Key        Value
    ---        -----
    role_id    <ROLE_ID>
    ```
  * Generate a Vault approle `secret_id`:

    Note: Vault secret_id should only need to be created (e.g., with `vault write -f...`) once. The generated secret_id should be passed in as an argument to the `installer/install.sh` script as shown below. The `install.sh` script will generate a new approle token with the secret_id.
    ```
    $ vault write -f auth/approle/role/rubin-data-dev.slac.stanford.edu/secret-id
    ```
  * Log in with approle (must be logged in as valid Vault user under same policy as approle):
    ```
    $ vault write auth/approle/login role_id='<ROLE_ID>' secret_id='<SECRET_ID>'
    ```

8. Add ArgoCD approle secret to Vault:

    Note: <BCRYPT_ARGO_ADMIN_PASSWORD> = Plaintext ArgoCD admin password from above, Base64 encoded. Example site used to generate encoding: https://www.base64decode.org/
    ```
    vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/argocd admin.password='<BCRYPT_ARGO_AMDIN_PASSWORD>' oidc.clientSecret='<ROLE_ID>' oidc.clientId='<SECRET_ID>' server.secretkey='<APPROLE_TOKEN>
    ```

9. Run install script with site name and Vault approle `secret_id`:
    ```
    $ ./install.sh usdfdev auth/approle/role/rubin-data-dev.slac.stanford.edu/role-id <SECRET_ID>
    ```

    the argo-repo-server pod needs to be on a node that can reach out to the internet (github).

    default of using git doens' twork for me, changed argocd app create to 

    ```
    argocd app create science-platform --repo https://github.com/yee379/phalanx.git --path science-platform --dest-namespace default --dest-server https://kubernetes.default.svc --upsert --revision master --port-forward --port-forward-namespace argocd --helm-set repoURL=https://github.com/yee379/phalanx.git --helm-set revision=master --values values-usdfdev.yaml
    ```



10. Create PersistentVolume for `Nublado2` JupyterHub:
    * Create yaml file `pv-jupyterhub-pod.yaml`:
    ```
    apiVersion: v1
    kind: PersistentVolume
    metadata:
        name: ocio-gpu01--hostpath
        labels:
            type: local
    spec:
        capacity:
            storage: 5Gi
    accessModes:
        - ReadWriteOnce
    persistentVolumeReclaimPolicy: Retain
    hostPath:
        path: "/mnt/nublado2"
    nodeAffinity:
        required:
            nodeSelectorTerms:
            - matchExpressions:
                - key: kubernetes.io/hostname
                  operator: In
                  values:
                  - ocio-gpu01
    ```
    * Create PV:
    ```
    kubectl -n nublado2 apply -f pv-jupyterhub-pod.yaml
    ```

11. Setup auth engine:
   ```
   vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/gafaelfawr auth_type=oidc
   ```

---

### Troubleshooting
- Installation issues
  * Expired OIDC token ("Unable to connect to the server: No valid id-token, and cannot refresh without refresh-token" error)
    * Solution: Log in to https://k8s-master-login.slac.stanford.edu and acquire new OIDC token before starting install.
  * ArgoCD times out when syncing `ingress-nginx` app during install
    * Solution: Comment out `ingress-nginx` in `install.sh`:
      ```
      echo "Syncing critical early applications"
      #argocd app sync ingress-nginx \
      #  --port-forward \
      #  --port-forward-namespace argocd
      ```
  * `helm template` command fails to deploy service
    * Solution: Create `services/<SERVICE_NAME>/values-usdfdev.yaml` with site-specific values as necessary.
