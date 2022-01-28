# rubin-deploy

Deployment notes and guide for USDF.

## Rubin Science Platform

The RSP is a jupyter notebook based user frontend system that allows users to analyse astronomical data. The RSP is ran on top of kubernetes.

The deployment engine is based upon argocd and utilises a hashicorp vault instance for password management. The deployment repo is called phalanx and consists of 'value' yaml files for each environment that provides site local overrides for the RSP.

SLAC currently maintains one environment for RSP:

- Staff RSP Dev: a development deployment of the RSP for Rubin Staff

TODO: probably want to rename usdfdev to usdf-staff-dev

### Pre-reqs

Secrets need to be generate for the system. A convenience script is provided under `phalanx/installer` directory.

```
❯ ./generate_secrets.py  usdf-staff-dev --regenerate
[pull-secret .dockerconfigjson] (.docker/config.json to pull images)
Current contents:

New filename with contents (empty to not change):
{}
[butler-secret aws-credentials.ini] (AWS credentials for butler)
Current contents:

New filename with contents (empty to not change):
{}
[butler-secret butler-gcs-idf-creds.json] (Google credentials for butler)
Current contents:

New filename with contents (empty to not change):
{}
[butler-secret postgres-credentials.txt] (Postgres credentials for butler)
Current contents:

New filename with contents (empty to not change):
{}
[tap google_creds.json] (file containing google service account credentials)
Current contents:

New filename with contents (empty to not change):
{}
[mobu ALERT_HOOK] (Slack webhook for reporting mobu alerts.  Or use None for no alerting.): [current: ]
[gafaelfawr cloudsql] (Use CloudSQL? (y/n):): [current: ] n
[gafaelfawr auth_type] (Use cilogon or github?): [current: ] github
[gafaelfawr github-client-secret] (GitHub client secret): [current: ] TBD
[installer argocd.admin.plaintext_password] (Admin password for ArgoCD?): [current: ] TBD
[argocd dex.clientSecret] (OAuth client secret for ArgoCD (either GitHub or Google)?): [current: ] GitHub
[vo-cutouts cloudsql] (Use CloudSQL? (y/n):): [current: ] n
[cert-manager enabled] (Use cert-manager? (y/n):): [current: ] n
[ingress-nginx tls.key] (Certificate private key)
Current contents:

New filename with contents (empty to not change):
{}
[ingress-nginx tls.crt] (Certificate chain)
Current contents:

New filename with contents (empty to not change):
{}
```

This will create a folder `secrets` in the directory.

In order to update the passwords into hashicopr vault, you must first obtain a token using

```
VAULT_ADDR=http://vault.slac.stanford.edu  vault login
```

Then push all the passwords to the appropriate location:

```
VAULT_PATH=secret/rubin/usdf-staffrsp-dev ./write_secrets.sh usdf-staffrsp-dev
```







# Deploy RSP using phalanx

- Forked https://github.com/lsst-sqre/phalanx to https://github.com/yee379/phalanx.
- Create new branch: `git checkout -b slac-initial-deploy`
- Install script under `installer/install.sh`
- Requires vault
- Requres yq binary - not in epel, download from https://github.com/mikefarah/yq
-- `wget https://github.com/mikefarah/yq/releases/download/v4.7.0/yq_linux_amd64 && chmod ugo+x yq_linux_amd64 && sudo mv yq_linux_amd64 /usr/local/bin/yq`
-- didn't really work, so just edit with `VAULT_PATH_PREFIX=$(cat ../science-platform/values-usdfdev.yaml | grep vault_path_prefix | awk '{print $2}')`
- modify `../science-platform/values-$ENVIRONMENT.yaml` for site
-- hardcoded to use vault.lsst.codes - modify to use slac's vault
- installs and overwrites vault-secret-operator secret; should investigate having multitenant vault operator? new vault CSI?
-- installs argocd from helm using serices/argocd/values-$ENV.yaml
- uses cert-manager via argocd; don't really need it as all traffic goes through f5's
- duplicate `science-platform/values-idfdev.yaml` to `science-platform/values-usdfdev.yaml`
-- changed: cert_issuer.enabled=false cert_manager.enabled=false gafaelfawr.enabled=false and ingress_nginx.enabled=false rancher_external_ip_webhook.enabled=false tap.enabled=false
-- using `vault_path_prefix=secret/rubin/rubin-data-dev.slac.stanford.edu`
- add secret `vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/installer argocd.admin.plaintext_password=<ARGO_ADMIN_PASSWORD>`

- installer users any token from VAULT - won't this persist with install?
-- enable an approle for this so we can impersonate it
- `vault auth enable approle`
-- create approle: ```vault write auth/approle/role/rubin-data-dev.slac.stanford.edu \
    secret_id_ttl=10m \
    token_num_uses=10 \
    token_ttl=20m \
    token_max_ttl=30m \
    secret_id_num_uses=40 \
    policies=rubin
```
-- ensure correct policy applied `vault write auth/approle/role/rubin-data-dev.slac.stanford.edu policies=rubin` # do not epire secret)
-- get role-id/client-id and secret-id
--- `vault read auth/approle/role/rubin-data-dev.slac.stanford.edu/role-id`
--- `vault write -f auth/approle/role/rubin-data-dev.slac.stanford.edu/secret-id`
-- login as approle `vault write auth/approle/login role_id='<OIDC_CLIENT_ID>' secret_id='<OIDC_CLIENT_SECRET>'`
-- use token provided to initiate the installer script

- duplicate services/argocd/values
- duplciate services/vault-secrets-operator/values

- ./install.sh usdfdev <token> ```
NAME                                                 READY   STATUS             RESTARTS   AGE
pod/argocd-application-controller-5c775c84c8-2wd6l   1/1     Running            0          6m10s
pod/argocd-dex-server-7d6b9d4f4b-fw4cv               0/1     CrashLoopBackOff   5          6m10s
pod/argocd-redis-68c7dff65b-jhqk4                    1/1     Running            0          6m10s
pod/argocd-repo-server-568bddfb5-hmrmt               1/1     Running            0          6m10s
pod/argocd-server-8659f697-82xfw                     0/1     CrashLoopBackOff   5          6m10s

❯ klf argocd-dex-server-7d6b9d4f4b-fw4cv
time="2021-04-21T23:57:32Z" level=fatal msg="secret \"argocd-secret\" not found"

❯ klf pod/argocd-server-8659f697-82xfw
time="2021-04-21T23:57:44Z" level=info msg="Starting configmap/secret informers"
time="2021-04-21T23:57:44Z" level=info msg="Configmap/secret informer synced"
time="2021-04-21T23:57:44Z" level=fatal msg="secret \"argocd-secret\" not found"
```
- prepopulate argo secrets `vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/argocd admin.password='<BCRYPT_ARGO_AMDIN_PASSWORD>' oidc.clientSecret='<OIDC_CLIENT_SECRET>' oidc.clientId='<OIDC_CLIENT_ID>' server.secretkey='<SERVER_SECRET>'`
-- where admin.password is bcrypted of `<ARGO_ADMIN_PASSWORD>` (note the $), and the others are from above
- i guess this is for image puling... `vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/pull-secret password=arghargh`

- populate some other vault secrets required:
-- `vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/pull-secret .dockerconfigjson='{}'`
-- `vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/nublado2 proxy_token='$(openssl rand -hex 32)' crypto_key='$(openssl rand -hex 32)'`
- create `services/nublado2/values-usdfdev.yaml`
- create pv for jupyterhub ```apiVersion: v1
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

- setup auth engine... ```vault kv put secret/rubin/rubin-data-dev.slac.stanford.edu/gafaelfawr auth_type=oidc```


