function Set-PathSlashes {
    param(
        [Parameter()]
        [string]
        $Path
    )
    if([environment]::OSVersion.Platform -eq "Win32NT") {
        $Path = $Path.Replace("/", "\")
    }elseif([environment]::OSVersion.Platform -eq "Unix") {
        $Path = $Path.Replace("/", "\")
    }elseif([environment]::OSVersion.Platform -eq "MacOSX") {
        $Path = $Path.Replace("/", "\")
    }elseif([environment]::OSVersion.Platform -eq "Linux") {
        $Path = $Path.Replace("/", "\")
    }
    return $Path 
}