require 'xcodeproj'

project_path = 'VPStudio.xcodeproj'
project = Xcodeproj::Project.open(project_path)

project.targets.each do |target|
  target.build_configurations.each do |config|
    config.build_settings['INFOPLIST_FILE'] = 'Info.plist'
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  end
end

project.save
puts "Successfully updated INFOPLIST_FILE path and reset GENERATE_INFOPLIST_FILE."
