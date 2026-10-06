# Getting Started with Helm

## Installing Helm

Follow this link: https://helm.sh/fr/docs/intro/install/
```bash
curl https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
```


## I - Helm = templating + packaging + deploy

Key idea: Helm is not just templating.<br>
→ It can **render**, **package**, and **deploy** to Kubernetes.

Prerequisites for helm install:
- A running Kubernetes cluster
- A working kubeconfig
- Ability to reach the cluster (e.g. *"kubectl get nodes"* works)

Helm uses the Kubernetes API to **apply** the rendered manifests.


## II - Using Helm after installation (basic workflow)

→ `<chart-name>` is the name you give to your Helm chart.<br>
By convention, it should match your project or application name (e.g. `myproject-frontend`).<br>
It becomes `.Chart.Name` in your templates and is used to build resource names.

```bash
# Create a new chart (in your project root repository):
helm create <chart-name>

# Install a release of that <chart-name>:
helm install <release-name> <chart-name>
# e.g. helm install myrelease mychart

# Upgrade an existing release:
helm upgrade <release-name> <chart-name>

# Uninstall (delete resources for this release):
helm uninstall <release-name> -n <namespace>

# List existing releases:
helm list -n <namespace>
```


## III. Key tree structure features

→ After typing `helm create <chart-name>`, you should get something like:

```yaml
myproject/
└─ <chart-name>/           # e.g. `mychart`
   ├─ Chart.yaml           # <- Important
   ├─ values.yaml          # <- Important
   └─ templates/
      ├─ configmap.yaml
      ├─ deployment.yaml
      ├─ ingress.yaml
      ├─ secret.yaml
      ├─ service.yaml
      ├─ _helpers.tpl      # <- Important
```

- `Chart.yaml`:
    - Metadata file for the chart: name, version, description, type.
    - Acts as the chart's "identity card".
    - Contains the `name: <chart-name>` field used as `.Chart.Name` in templates.
- `values.yaml`:
    - Default configuration values for the chart.
    - All values defined here are accessible in templates via `.Values.<key>`.
    - Can be overridden at install/upgrade time with `--set` or `--values`.
- `templates.yaml`:
    - Directory containing all Kubernetes manifest templates (.yaml files).
    - Helm renders these files by injecting values **from values.yaml** and release metadata (**.Release.Name**, **.Chart.Name**, etc.).
    - e.g.: `configmap.yaml` template is a template fulfilled with corresponding values in values.yaml.
- `_helpers.tpl`:
    - A special non-rendered file (prefixed with `_`) that defines reusable named template helpers (e.g. `myproject.fullname`, `myproject.labels`).
    - These helpers are called with `{{ include "..." . }}` inside the other templates to avoid duplication.


## IV - What is the Helm Release Name ?

- The **Release Name** is the name you give to **one deployed instance** of your chart.
- Syntax:
```bash
helm install <release-name> <chart-name>
# e.g.
helm install myrelease mychart
# helm install myrelease ./mychart
```

Here:
- mychart = the **Chart** (your packaged app / your **project**)
- myrelease = **Release Name**<br>

If you do:
```bash
helm install dev mychart
helm install prod mychart
helm install clientA mychart
```

→ You create **3 isolated installations** of the same chart (*mychart*), each with a different Release Name.


## V - Why do we need the Release Name ?

- Kubernetes **refuses** two resources with the same name in the same namespace.
- Just using the chart name is **not enough**:
```bash
myproject-frontend (Chart.Name)
```

-→ If two teams install your chart in the same cluster:
```bash
helm install myrelease mychart
helm install prodrelease mychart
```

-→ They each get a full copy of:
- Secret
- ConfigMap
- Deployment
- Service

To avoid name collisions, Helm combines:
```bash
Chart.Name + Release.Name
```

→ That’s what we call it the **fullname**.


## VI - Name vs fullname helpers - *`_helpers.tpl`* file (best practice)
Helper definitions
```bash
{{- define "projectname.name" -}}
{{ .Chart.Name }}
{{- end }}

{{- define "projectname.fullname" -}}
{{ printf "%s-%s" .Chart.Name .Release.Name }}
{{- end }}
```

**Why this pattern ?**
- name = **pure chart name**
    - → Comes from **.Chart.Name** (i.e. uses `name:` field from `Chart.yaml` file)
    - → Used for labels, static strings
    - → Must **not** depend on .Release.Name

- fullname = **unique name generated for Kubernetes**
    - → Must include **.Release.Name**
    - → Used for real resource names (Secret / ConfigMap / Deployment / Service)

**Usage summary**
- name → recommended value: **.Chart.Name**
    - → use for **container names, labels**

- fullname → recommended value: **.Chart.Name + .Release.Name**
    - → use for **real resource names** (Secret, ConfigMap, Deployment, Service, etc.)


## VII - Concrete example with "`dev`" release name (& with the "`myproject-frontend`" chart name)

Command:
```bash
helm install dev ./myproject-frontend
```

Then:
- **.Release.Name** = **dev**
- **.Chart.Name** = **myproject-frontend**

→ So the **fullname** becomes:
```bash
myproject-frontend-dev
```

And your resources (with suffixes that YOU add) become, for example :
```txt
- Secret : myproject-frontend-dev-secret
- ConfigMap : myproject-frontend-dev-config
- Deployment : myproject-frontend-dev-deployment
- Service : myproject-frontend-dev-service
```

That’s the Helm mechanics:
- name = stable chart name,
- fullname = **Chart.Name + Release.Name**, then you add your own suffixes (`-secret`, `-config`, `-deployment`, etc.) as needed.

> **Note:** The default `_helpers.tpl` generated by `helm create` uses `Release.Name + Chart.Name` (e.g. `dev-myproject-frontend`).<br>
The pattern above (`Chart.Name + Release.Name`) matches the convention defined in your own `_helpers.tpl` and the `fullnameOverride: "myproject-frontend-dev"` set in your `values.yaml`.


## VIII - Main commands & roles<br>
**Command**	                                         **Role**
```bash
helm create <chart-name>                             # Create a new Helm chart with a basic structure

helm template <release-name> <chart-name>            # Render YAML locally to raw YAML for inspection, **but do not deploy** anything

helm lint <chart-name>                               # Validate the structure and syntax of a chart

helm install <release-name> <chart-name>	         # Render YAML **and send it to Kubernetes** (installs a new release of the chart into the cluster)

helm install --values=<my-values.yaml> <chart-name>  # Value injection (from another values.yaml file) into existing <chart-name> template files

helm install --set version=2.0.0                     # Override values - if `values.yaml` gets a `version:` parameter in that example

helm upgrade <release-name> <chart-name>	         # Re-render and apply **only the differences** for an existing release (updates an existing release with new templates or values.)

helm rollback <release-name> <chart-name>            # Roll back a release to a previous revision (use `helm history <release-name>` to list revisions)

kubectl apply -f <yaml-template-file>                # Apply **already rendered** YAML
```


## IX - Just render the YAML (no cluster needed)

If you only want to **see what Helm generates** without deploying:

Command:
```bash
helm template <release-name> <chart-name> 
```

Result:<br>
→ Helm prints the **final YAML** to stdout, **without modifying your cluster**.

You can verify all substitutions:
- names
- configmap
- secret
- deployment
- service
- ingress
- etc.

## Alternative: render to a file

```bash
helm template <release-name> <chart-name> > rendered.yaml
# e.g.helm template dev myproject-frontend > rendered.yaml
```
→ You get a rendered.yaml file.<br>
→ Useful to:
- fix raw YAML errors
- spot {{ }} templating issues
- validate your chart structure

→ All of that works **without any Kubernetes cluster**.


## X - Practical summary: which command for which need ?

Need → Helm command

**Need**	                                                            **Helm command**
```txt
Validate the chart structure	                                        helm lint <chart-name>

Just see the rendered YAML	                                            helm template <release-name> <chart-name>

Deploy to Kubernetes	                                                helm install <release-name> <chart-name>

Update an existing deployment	                                        helm upgrade <release-name> <chart-name>

Remove a release (and its associated resources) from the cluster	    helm uninstall <release-name> -n <namespace>
```

Conclusion:
- Helm is a **rendering**, **packaging** and **deployment** tool.
- `helm install` **really applies resources to your cluster**.
- If you only want the rendered YAML, use `helm template` instead.

------

→ With this template, you just have to change values into **values.yaml** file.<br>
→ No need to even change **Chart.yaml**, but you can do it.
→ Just:<br>
    - Set `fullnameOverride` in **values.yaml** to the desired resource name (e.g. `"myproject-frontend-dev"`), so Kubernetes resource names are fully controlled regardless of the release name.
    - Execute that command into your project repository: `helm install <your-release> ./mychart` (the one which is attached to this documentation).
