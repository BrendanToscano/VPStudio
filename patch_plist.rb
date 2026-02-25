require 'xcodeproj'

project_path = 'VPStudio.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings.delete('INFOPLIST_KEY_NSAppTransportSecurity')
    config.build_settings['INFOPLIST_FILE'] = 'VPStudio/Info.plist'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
  end
end

project.save
puts "Successfully updated Xcode project to stop generating double Info.plist files."
