<#
.Synopsis
   Substitution for 'Invoke-WebRequest' cmdlet that can run on Nano and ServerCore.
.DESCRIPTION
   Light implementation of the Invoke-WebRequest cmdlet, but adding support for Nano 
   and automating file unzipping operations.  Allows basic 'curl'-like functionality in Dockerfiles.
.EXAMPLE
   $response=Get-WebStuff -GetUri 'https://github.com/PowerShell/PowerShell/releases/latest'
   Makes the webcall and returns response object:
   PS C:\>$response|get-member #inspect and parse output in your code
      TypeName: System.Net.Http.HttpResponseMessage
      
.EXAMPLE
   $directory=Get-WebStuff -GetUri $httpMyFileDotZipUrl -TimeOutMin=30 -Destination 'C:\DownloadDir -UnZip

   Downloads and unzips 'https://github.com/PowerShell/PowerShell/.../powershell-6.0.0-alpha-win10-x64.zip'
   PS C:\Windows\system32> dir $directory   #returns a DirectoryInfo object to the unzipped file.
      Directory: C:\DownloadDir
    Mode                LastWriteTime         Length Name
    ----                -------------         ------ ----
    d-----        10/6/2016   8:38 PM                assets
    d-----        10/6/2016   8:38 PM                Modules
    
.EXAMPLE
   $file=Get-WebStuff -GetUri 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' -Destination 'C:\DownloadDir\NuGet.exe'
   
   Copies 'https://dist.nuget.org/win-x86-commandline/latest/nuget.exe' to 'C:\DownloadDir\NuGet.exe'...
   PS C:\> .$file   #returns FileInfo object for your download.
      NuGet Version: 3.4.4.1321
      usage: NuGet <command> [args] [options]
      Type 'NuGet help <command>' for help on a specific command.
#> 
Function Get-WebStuff ([System.URI]$GetUri, [System.Int32]$TimeOutMin='2', [System.IO.FileInfo]$Destination, [switch]$UnZip)
{   
    #Using System.Net.Http (instead of System.Net.WebClient) so this can work on Nano too. 
    if (-not($GetUri -as [System.URI]).AbsoluteURI) {throw "Invalid URL: '$GetUri'"}
    Add-Type -AssemblyName 'System.Net.Http'
    $handler = New-Object System.Net.Http.HttpClientHandler
    $client  = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout  = New-Object System.TimeSpan(0, $TimeOutMin, 0)
    $cancelTokenSource = [System.Threading.CancellationTokenSource]::new()
    $responseMsg = $client.GetAsync([System.Uri]::new($GetUri), $cancelTokenSource.Token)
    Write-Host "Making WebRequest to '$GetUri'..."
    $responseMsg.Wait()
    $client.Dispose();$cancelTokenSource.Dispose();$handler.Dispose()
    if (!$responseMsg.IsCanceled)
    {  
      $response = $responseMsg.Result
      if ($response.IsSuccessStatusCode)
      {
        if ($Destination) 
        {
          if (Test-Path $Destination)
          {
            Write-Host ("Removing existing files under '"+$Destination.FullName+"'...")
            Remove-Item -Path $Destination -Force -Recurse -ErrorAction Stop 
          }
          [System.Io.FileInfo]$tempFile = [System.IO.Path]::GetTempFileName()
          Write-Host ("Writing response to '"+($tempFile.FullName)+"'...")
          $downloadedFileStream = [System.IO.FileStream]::new($tempFile, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
          $copyStreamOp = $response.Content.CopyToAsync($downloadedFileStream)
          $copyStreamOp.Wait()
          $downloadedFileStream.Close()
          if ($copyStreamOp.Exception -ne $null)
          {
            throw $copyStreamOp.Exception
          }
          $client.Dispose();$cancelTokenSource.Dispose();$handler.Dispose()
          if ($UnZip)
          {              
            Write-Host ("Extracting new files to '"+$Destination.FullName+"'...")
            try {
              Add-Type -AssemblyName System.IO.Compression.FileSystem
            } catch  {
              Add-Type -AssemblyName System.IO.Compression.ZipFile
            } finally {
              [System.IO.Compression.ZipFile]::ExtractToDirectory($tempFile,$Destination)
            }
              Write-Host ("Deleting tmp file '"+$tempFile.FullName+"'...")
              Remove-Item $tempFile -ErrorAction Continue
            } else {
              Write-Host ("Copying new file to '"+$Destination.FullName+"'...")
              Move-Item -Path $tempFile -Destination $Destination -Force -ErrorAction Stop
            }                
              return $Destination
            } else {
              $client.Dispose();$cancelTokenSource.Dispose();$handler.Dispose()
              Write-Host "WebRequest completed successfully"
              return $response
          }
        } else {
          write-verbose ($response.ToString())
          throw "Request to '$GetUri' failed"
        }        
    } else {
      write-error "Request to '$GetUri' timed out."
      return $responseMsg
    }
}
<#
.Synopsis
   Downloads and extracts PowerShell release.zip on Nano or ServerCore.
.DESCRIPTION
   Downloads and extracts PowerShell release.zip on Nano or ServerCore.
   Usefull for installing latest release of PowerShell in Docker Containers
.EXAMPLE
   Get-LatestPS
   Downloads the latest and extracts it to C:\PowerShell by default
   Will no-op if existing build matches the latest.
#>
Function Get-LatestPs (
  [System.URI]$GetUri = 'https://github.com/PowerShell/PowerShell/releases/latest/',
  [System.String]$FileSuffix = '-win10-x64.zip',
  [System.IO.FileInfo]$DestinationPath = $Env:SystemDrive+'\PowerShell'
)
{
  $response=Get-WebStuff -GetUri $gitUri -TimeOutMin 3 -ErrorAction Stop
  $gitTag = ($response.RequestMessage.RequestUri.AbsoluteUri.split("/"))[-1].TrimStart('v')
  $downloadFile = 'powershell-' + $gitTag + '-win10-x64.zip'
  Write-Host ("Latest release is '"+$downloadFile+"'")
  $downloadUri = ($response.RequestMessage.RequestUri.AbsoluteUri.Replace('tag','download')) + '/' + $downloadFile
  if ([String]$(Get-Content -Path $DestinationPath\.dlsource.txt -ErrorAction Ignore)  -eq $downloadUri)
  {
    Write-Host ("Latest release is already present in '"+$DestinationPath.FullName+"'.  Exiting...")
    return "no new build to test" #no-op and exit
  } else {
    $response=Get-WebStuff -GetUri $downloadUri -TimeOutMin 30 -Destination $DestinationPath -UnZip -ErrorAction Stop
    Write-Host ("Logging download source URL to '"+($destinationPath.FullName + '\.dlsource.txt')+"'.")
    $downloadUri | out-file -FilePath ($destinationPath.FullName + '\.dlsource.txt')
    return ("New build successfully downloaded to '"+$destinationPath.FullName+"'.")
  }
}