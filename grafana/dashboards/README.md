# Grafana Dashboard Configuration

## Updating Datasource UID

The dashboard JSON files in this directory reference datasources using a unique identifier (UID). If you need to update the datasource UID to match your Grafana instance, follow the instructions below.

### Method 1: Grafana UI (Easiest)

1. Navigate to **Grafana** → **Connections** → **Data sources**
2. Click on the datasource you want to use (e.g., **Prometheus**)
3. Look at the **URL in your browser's address bar**
4. The UID will be visible in the URL (typically after `/datasources/edit/`)
   - Example: `http://localhost:3000/datasources/edit/prometheus` → UID is `prometheus`

### Updating the Dashboard Files

Once you have the UID, you can update it in the dashboard JSON files:

Find sections like this:

```json
"datasource": {
  "type": "prometheus",
  "uid": "prometheus"
}
```

Replace the `"uid"` value with the UID you found in step 3 above.

### Note

- The default UID for Prometheus in these dashboards is `prometheus`
- If your Grafana instance uses a different UID, you'll need to update all dashboard files accordingly
- You can use a find-and-replace tool to update multiple files at once

