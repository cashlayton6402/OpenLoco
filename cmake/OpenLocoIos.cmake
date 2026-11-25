# The first iOS target is an asset-free setup shell, linked against the full core.
# Gameplay startup and original-data import follow in separately approved stages.
set(OPENLOCO_IOS_BUNDLE_ID "io.openloco.ios.development" CACHE STRING "Unsigned iOS bundle identifier")
set(OPENLOCO_IOS_BUILD_NUMBER "1" CACHE STRING "Numeric iOS build number")

set_target_properties(App PROPERTIES
    MACOSX_BUNDLE ON
    MACOSX_BUNDLE_INFO_PLIST "${CMAKE_SOURCE_DIR}/distribution/ios/Info.plist.in"
    MACOSX_BUNDLE_GUI_IDENTIFIER "${OPENLOCO_IOS_BUNDLE_ID}"
    MACOSX_BUNDLE_BUNDLE_NAME OpenLoco
    XCODE_ATTRIBUTE_PRODUCT_BUNDLE_IDENTIFIER "${OPENLOCO_IOS_BUNDLE_ID}"
    XCODE_ATTRIBUTE_TARGETED_DEVICE_FAMILY "2"
    XCODE_ATTRIBUTE_CODE_SIGNING_ALLOWED NO
    XCODE_ATTRIBUTE_CODE_SIGNING_REQUIRED NO
    XCODE_ATTRIBUTE_GENERATE_INFOPLIST_FILE NO
    XCODE_ATTRIBUTE_ASSETCATALOG_COMPILER_APPICON_NAME AppIcon
    XCODE_ATTRIBUTE_CLANG_ENABLE_OBJC_ARC YES
    XCODE_ATTRIBUTE_DEAD_CODE_STRIPPING NO
    XCODE_ATTRIBUTE_DEBUG_INFORMATION_FORMAT "dwarf-with-dsym")

# A setup-only shell otherwise leaves much of the core archive unreferenced.
# Force it into the link so the unsigned spike actually verifies engine symbols.
target_link_options(App PRIVATE "LINKER:-force_load,$<TARGET_FILE:OpenLoco>")
target_link_libraries(App PRIVATE "-framework UIKit" "-framework Foundation")

set(ios_asset_catalog "${CMAKE_CURRENT_BINARY_DIR}/Assets.xcassets")
file(MAKE_DIRECTORY "${ios_asset_catalog}/AppIcon.appiconset")
configure_file("${CMAKE_SOURCE_DIR}/distribution/ios/AssetCatalogContents.json"
    "${ios_asset_catalog}/Contents.json" COPYONLY)
configure_file("${CMAKE_SOURCE_DIR}/src/Resources/src/logo/icon_x1024.png"
    "${ios_asset_catalog}/AppIcon.appiconset/AppIcon.png" COPYONLY)
configure_file("${CMAKE_SOURCE_DIR}/distribution/ios/AppIconContents.json"
    "${ios_asset_catalog}/AppIcon.appiconset/Contents.json" COPYONLY)
target_sources(App PRIVATE "${ios_asset_catalog}")
set_source_files_properties("${ios_asset_catalog}" PROPERTIES MACOSX_PACKAGE_LOCATION Resources)

file(GLOB ios_languages CONFIGURE_DEPENDS "${CMAKE_SOURCE_DIR}/data/language/*")
file(GLOB_RECURSE ios_objects CONFIGURE_DEPENDS "${openloco_objects_SOURCE_DIR}/*")
set(ios_notices "${CMAKE_SOURCE_DIR}/LICENSE" "${CMAKE_SOURCE_DIR}/CONTRIBUTORS.md")
target_sources(App PRIVATE ${ios_languages} ${ios_objects} ${ios_notices})
set_source_files_properties(${ios_languages} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/language")
set_source_files_properties(${ios_objects} PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/objects")
set_source_files_properties(${ios_notices} PROPERTIES MACOSX_PACKAGE_LOCATION Resources)
