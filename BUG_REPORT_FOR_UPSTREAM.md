# Bug Report: Missing package-lock.json Files Break `azd up` Deployment

## Summary

The `grocery-sre-demo` repository fails during `azd up` deployment because the Dockerfiles use `npm ci --only=production`, but the required `package-lock.json` files are excluded by `.gitignore`.

## Environment

- **Repository:** https://github.com/dm-chelupati/grocery-sre-demo
- **Command:** `azd up`
- **Platform:** macOS (but issue is platform-independent)
- **Docker:** Docker Desktop
- **Node.js:** v20-alpine (from Dockerfile)

## Error Details

### Error Message
```
npm error code EUSAGE
npm error
npm error The `npm ci` command can only install with an existing package-lock.json or
npm error npm-shrinkwrap.json with lockfileVersion >= 1. Run an install with npm@5 or
npm error later to generate a package-lock.json file, then try again.
```

### Full Error Output
```
#9 [4/5] RUN npm ci --only=production
#9 1.159 npm error code EUSAGE
#9 1.159 npm error The `npm ci` command can only install with an existing package-lock.json
#9 ERROR: process "/bin/sh -c npm ci --only=production" did not complete successfully: exit code: 1
```

### Affected Files
- `src/api/Dockerfile` (line 6)
- `src/web/Dockerfile` (line 6)

Both Dockerfiles contain:
```dockerfile
RUN npm ci --only=production
```

But `.gitignore` contains:
```
package-lock.json
```

## Root Cause

The `.gitignore` file excludes `package-lock.json` files, but the Docker build process requires them for the `npm ci` command to work. The `npm ci` command is stricter than `npm install` and requires an exact lockfile.

## Impact

- ❌ `azd up` deployment fails
- ❌ Cannot build Docker images locally
- ❌ CI/CD pipelines would fail
- ❌ Users following the README cannot deploy the demo

## Proposed Solutions

### Option 1: Commit package-lock.json Files (Recommended)

**Pros:**
- Ensures reproducible builds
- Follows npm best practices for production deployments
- Works with `npm ci` as intended
- Faster CI/CD builds

**Cons:**
- Lock files in source control (though this is actually recommended)

**Implementation:**
```bash
# Generate lock files
cd src/api && npm install
cd ../web && npm install

# Commit them (overriding .gitignore)
git add -f src/api/package-lock.json src/web/package-lock.json
git commit -m "fix: Add package-lock.json files required for npm ci in Dockerfile"
```

**Update `.gitignore`:**
```diff
- package-lock.json
+ # package-lock.json should be committed for production deployments
```

### Option 2: Change Dockerfile to Use `npm install`

**Pros:**
- Works without lock files
- No need to change .gitignore

**Cons:**
- Non-reproducible builds
- Slower installations
- Can introduce dependency conflicts
- Not following npm best practices

**Implementation:**
Update both `src/api/Dockerfile` and `src/web/Dockerfile`:
```dockerfile
# Before
RUN npm ci --only=production

# After
RUN npm install --omit=dev
```

### Option 3: Generate Lock File During Build

**Pros:**
- Lock files not in source control
- Still uses npm ci

**Cons:**
- Requires multi-stage build
- More complex Dockerfile
- Defeats purpose of deterministic builds

**Implementation:**
```dockerfile
# Generate lock file, then install
RUN npm install --package-lock-only && \
    npm ci --only=production
```

## Recommendation

**Use Option 1** - Commit the lock files.

This is the industry standard practice for production deployments and aligns with npm's recommendations. The `package-lock.json` files ensure:
- Reproducible builds across environments
- Faster CI/CD pipelines
- Protection against breaking changes in transitive dependencies
- Exact same dependency tree every deployment

## Testing the Fix

After applying Option 1:

```bash
# Clean any existing builds
azd down --purge --force

# Deploy from scratch
azd up
```

**Expected Result:**
```
SUCCESS: Your up workflow to provision and deploy to Azure completed in 4 minutes 22 seconds.
```

## Additional Notes

### Current package.json Dependencies

**API (`src/api/package.json`):**
```json
{
  "dependencies": {
    "express": "^4.18.2",
    "winston": "^3.11.0",
    "winston-loki": "^6.0.8",
    "prom-client": "^15.1.0"
  }
}
```

**Web (`src/web/package.json`):**
```json
{
  "dependencies": {
    "express": "^4.18.2",
    "ejs": "^3.1.9",
    "axios": "^1.6.2"
  }
}
```

All dependencies use caret ranges (`^`), which means minor/patch updates are allowed. Without lock files, different developers/environments could get different versions.

## References

- [npm ci documentation](https://docs.npmjs.com/cli/v9/commands/npm-ci)
- [Should I commit package-lock.json?](https://docs.npmjs.com/cli/v9/configuring-npm/package-lock-json#package-lockjson-vs-npm-shrinkwrapjson)
- [Azure Developer CLI (azd) documentation](https://learn.microsoft.com/azure/developer/azure-developer-cli/)

## Verified Fix

I have applied Option 1 in my fork and confirmed successful deployment:

✅ Docker images build successfully  
✅ `azd up` completes without errors  
✅ Container Apps deployed and running  
✅ API endpoint accessible  
✅ Web frontend accessible  

**Deployment Time:** 4 minutes 22 seconds

---

**Reported by:** Arturo Quiroga (Microsoft)  
**Date:** January 28, 2026  
**Related Blog:** [How SRE Agent Pulls Logs from Grafana and Creates Jira Tickets Without Native Integrations](https://techcommunity.microsoft.com/blog/azurepaasblog/introducing-azure-sre-agent/4414569)
