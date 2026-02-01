# Deploy ComfyUI Controller to Google Cloud Run

This guide sets up a web interface for controlling ComfyUI on RunPod, secured with your Google account.

## Prerequisites

- Google Cloud account with billing enabled
- `gcloud` CLI installed

## Step 1: Install gcloud CLI (if needed)

```bash
brew install google-cloud-sdk
```

## Step 2: Login and Set Project

```bash
# Login to Google Cloud
gcloud auth login

# Create a new project (or use existing)
gcloud projects create comfyui-controller --name="ComfyUI Controller"

# Set as active project
gcloud config set project comfyui-controller

# Enable billing (required) - do this in the console:
# https://console.cloud.google.com/billing/linkedaccount?project=comfyui-controller
```

## Step 3: Enable Required APIs

```bash
gcloud services enable \
    cloudbuild.googleapis.com \
    run.googleapis.com \
    iap.googleapis.com \
    artifactregistry.googleapis.com
```

## Step 4: Deploy to Cloud Run

```bash
cd "/Users/moserrs/Desktop/Comfy CLI/web-app"

# Deploy (this builds and deploys in one step)
gcloud run deploy comfyui-controller \
    --source . \
    --region us-central1 \
    --allow-unauthenticated \
    --set-env-vars="RUNPOD_API_KEY=your_runpod_api_key,RUNPOD_VOLUME_ID=your_volume_id"
```

This will output a URL like: `https://comfyui-controller-xxxxx-uc.a.run.app`

## Step 5: Set Up Google Sign-In (IAP)

Since Cloud Run's built-in IAP requires a load balancer ($$), we'll use a simpler approach - add authentication directly to the app.

### Option A: Quick & Simple - Remove Public Access

Instead of IAP, we can make the Cloud Run service require authentication:

```bash
# Remove public access
gcloud run services update comfyui-controller \
    --region us-central1 \
    --no-allow-unauthenticated

# Give yourself access
gcloud run services add-iam-policy-binding comfyui-controller \
    --region us-central1 \
    --member="user:YOUR_EMAIL@gmail.com" \
    --role="roles/run.invoker"
```

Then access via the `gcloud` proxy:
```bash
gcloud run services proxy comfyui-controller --region us-central1
```

### Option B: Use Identity Platform (Recommended for iPad)

For a proper login page on iPad, we need to add Firebase Auth to the app. Let me know if you want me to set this up - it adds a Google Sign-In button to the web interface.

### Option C: Simple Password Protection

Add a password check to the app - simpler but less secure than Google Sign-In.

## Step 6: Access from iPad

Once deployed, bookmark the Cloud Run URL on your iPad:

1. Open Safari
2. Go to your Cloud Run URL
3. Add to Home Screen (Share → Add to Home Screen)

This creates an app-like icon that opens the controller.

## Costs

- **Cloud Run**: Free tier includes 2 million requests/month
- **Artifact Registry**: ~$0.10/GB/month for container storage
- **Estimated monthly cost**: < $1/month for typical usage

## Updating the App

After making changes, redeploy:

```bash
cd "/Users/moserrs/Desktop/Comfy CLI/web-app"
gcloud run deploy comfyui-controller --source . --region us-central1
```

## Troubleshooting

**"Permission denied" errors:**
```bash
gcloud auth application-default login
```

**View logs:**
```bash
gcloud run logs read comfyui-controller --region us-central1
```

**Delete everything:**
```bash
gcloud run services delete comfyui-controller --region us-central1
gcloud projects delete comfyui-controller
```
