# scoop-www

Private Scoop bucket for personal Windows apps.

```powershell
scoop bucket add www https://github.com/nonlog/scoop-www.git
scoop install www/<app>
```

The `Excavator` workflow uses `ScoopInstaller/GithubActions` every six hours to run Scoop checkver/autoupdate and commit manifest updates when upstream releases publish matching Windows assets.
