Pod::Spec.new do |s|
  s.name             = 'sensor_availability'
  s.version          = '0.0.1'
  s.summary          = 'Module 7 - Device Sensor Availability detection.'
  s.description      = <<-DESC
Existence checks for 26 hardware sensors at app init.
                       DESC
  s.homepage         = 'https://github.com/rescate'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Rescate' => 'noreply@rescate.dev' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version    = '5.0'
end
