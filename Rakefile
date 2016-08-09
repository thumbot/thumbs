task :default => [:test]

task :test do
  ruby FileList.new('test/*.rb')
end

task :start do
  ruby "./app.rb -p 4567"
end

