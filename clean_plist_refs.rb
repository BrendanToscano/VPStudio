require 'xcodeproj'

project_path = 'VPStudio.xcodeproj'
project = Xcodeproj::Project.open(project_path)

# Remove Info.plist from any target resources or group
project.targets.each do |target|
  target.resources_build_phase.files.each do |file|
    if file.file_ref && file.file_ref.path =~ /Info.plist$/
      puts "Removing from resources: #{file.file_ref.path}"
      file.remove_from_project
    end
  end
  target.source_build_phase.files.each do |file|
    if file.file_ref && file.file_ref.path =~ /Info.plist$/
      puts "Removing from sources: #{file.file_ref.path}"
      file.remove_from_project
    end
  end
end

project.main_group.recursive_children.each do |file|
  if file.is_a?(Xcodeproj::Project::Object::PBXFileReference) && file.path =~ /Info.plist$/
    puts "Removing file reference: #{file.path}"
    file.remove_from_project
  end
end

project.save
puts "Successfully cleaned project file."
