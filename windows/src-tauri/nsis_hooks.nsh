; Hook de NSIS para Side B Windows
; Garantiza que libmpv-2.dll esté en el directorio raíz del ejecutable instalado

!macro NSIS_HOOK_POSTINSTALL
  ; Si ya está en la raíz, no hacer nada
  IfFileExists "$INSTDIR\libmpv-2.dll" end_mpv_postinstall 0
  ; Si quedó en resources, copiar a raíz
  IfFileExists "$INSTDIR\resources\libmpv-2.dll" 0 check_up_dir
    CopyFiles /SILENT "$INSTDIR\resources\libmpv-2.dll" "$INSTDIR\libmpv-2.dll"
    Goto end_mpv_postinstall
  check_up_dir:
  ; Si Tauri normalizó el path como _up_\.cache\mpv
  IfFileExists "$INSTDIR\_up_\.cache\mpv\libmpv-2.dll" 0 check_any_dll
    CopyFiles /SILENT "$INSTDIR\_up_\.cache\mpv\libmpv-2.dll" "$INSTDIR\libmpv-2.dll"
    RMDir /r "$INSTDIR\_up_"
    Goto end_mpv_postinstall
  check_any_dll:
  IfFileExists "$INSTDIR\resources\*.dll" 0 end_mpv_postinstall
    CopyFiles /SILENT "$INSTDIR\resources\*.dll" "$INSTDIR\"
  end_mpv_postinstall:
  ; El loader Vulkan es una dependencia transitiva de libmpv.
  IfFileExists "$INSTDIR\vulkan-1.dll" end_vulkan_postinstall 0
  IfFileExists "$INSTDIR\resources\vulkan-1.dll" 0 end_vulkan_postinstall
    CopyFiles /SILENT "$INSTDIR\resources\vulkan-1.dll" "$INSTDIR\vulkan-1.dll"
  end_vulkan_postinstall:
  IfFileExists "$INSTDIR\VulkanRT-License.txt" end_vulkan_license 0
  IfFileExists "$INSTDIR\resources\VulkanRT-License.txt" 0 end_vulkan_license
    CopyFiles /SILENT "$INSTDIR\resources\VulkanRT-License.txt" "$INSTDIR\VulkanRT-License.txt"
  end_vulkan_license:
!macroend

!macro NSIS_HOOK_PREUNINSTALL
  Delete "$INSTDIR\libmpv-2.dll"
  Delete "$INSTDIR\vulkan-1.dll"
  Delete "$INSTDIR\VulkanRT-License.txt"
  RMDir /r "$INSTDIR\_up_"
!macroend
