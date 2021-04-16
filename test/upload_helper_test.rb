$:.unshift File.join(File.dirname(__FILE__),"..","lib")
$:.unshift File.join(File.dirname(__FILE__))

require 'minitest/autorun'
require 'rim/git'
require 'rim/module_info'
require 'rim/rim_info'
require 'rim/status_builder'
require 'rim/sync_helper'
require 'rim/upload_helper'
require 'test_helper'
require 'fileutils'

class UploadHelperTest < Minitest::Test
  include FileUtils
  include TestHelper

  def setup
    test_dir = empty_test_dir("upload_helper_test")
    @remote_git_dir = File.join(test_dir, "remote_git")
    @ws_remote_dir = File.join(test_dir, "remote_ws")
    @ws_dir = File.join(test_dir, "ws")
    @logger = Logger.new($stdout)
    @logger.level = Logger::ERROR unless ARGV.include? "debug"
    RIM::GitSession.logger = @logger
  end
  
  def teardown
    remove_test_dirs
  end

  def test_no_files_are_uploaded_if_not_dirty
    mod1_info = create_module_git("mod1")
    sha1 = nil
    module_session(mod1_info) do |s|
      sha1 = s.rev_sha1("HEAD")  
    end 
    mod2_info = create_module_git("mod2")
    create_ws_git("testbr")
    sync_helper = RIM::SyncHelper.new(@ws_dir, @logger, [mod1_info, mod2_info])
    sync_helper.sync
    RIM::git_session(@ws_dir) do |s|
      s.execute("git rebase rim/testbr")
    end
    cut = RIM::UploadHelper.new(@ws_dir, true, @logger, [mod1_info, mod2_info])
    cut.upload
    module_session(mod1_info) do |s|
      assert s.rev_sha1("master") == sha1
    end
  end
  
  def test_files_of_new_commits_are_uploaded
    mod1_info = create_module_git("mod1")
    create_ws_git("testbr")
    sync_helper = RIM::SyncHelper.new(@ws_dir, @logger, [mod1_info])
    sync_helper.sync
    RIM::git_session(@ws_dir) do |s|
      s.execute("git rebase rim/testbr")
    end
    shas = []
    # make two changes to module
    RIM::git_session(@ws_dir) do |s|
      `echo ' appended' >> #{File.join(@ws_dir, "mod1/readme.txt")}`
      s.execute("git commit . -m \"First change\"")
      shas.push(s.rev_sha1("HEAD"))  
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Second change\"")
      shas.push(s.rev_sha1("HEAD"))  
    end
    cut = RIM::UploadHelper.new(@ws_dir, true, @logger, [mod1_info])
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout master")
      assert File.exist?(File.join(@remote_git_dir, "mod1/readme.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/new_file.txt"))
      assert s.execute("git show -s --format=%B HEAD").start_with?("Second change")
      assert s.execute("git show -s --format=%B HEAD~1").start_with?("First change") 
    end
  end

  def test_files_of_new_commits_are_uploaded_subdir
    mod_git_dir = create_all_module_git("mod_all")
    mod_a_info =  RIM::ModuleInfo.new("file://" + mod_git_dir, "modules/a", "master", nil, nil, nil, "mod_a")
    create_ws_git("testbr")
    sync_helper = RIM::SyncHelper.new(@ws_dir, @logger, [mod_a_info])
    sync_helper.sync
    RIM::git_session(@ws_dir) do |s|
      s.execute("git rebase rim/testbr")
    end
    shas = []
    # make two changes to module
    RIM::git_session(@ws_dir) do |s|
      `echo ' appended' >> #{File.join(@ws_dir, "modules/a/file_a.c")}`
      s.execute("git commit . -m \"First change\"")
      shas.push(s.rev_sha1("HEAD"))
      `echo 'Test' > #{File.join(@ws_dir, "modules/a/new_file.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Second change\"")
      shas.push(s.rev_sha1("HEAD"))
    end
    cut = RIM::UploadHelper.new(@ws_dir, true, @logger, [mod_a_info])

    module_session(mod_a_info) do |s|
      s.execute("git checkout --detach master")
      assert File.exist?(File.join(mod_git_dir, "mod_a", "file_a.c"))
      assert !File.exist?(File.join(mod_git_dir, "mod_a", "new_file.txt"))
      assert File.exist?(File.join(mod_git_dir, "mod_b", "src", "file_b.c"))
    end

    cut.upload

    module_session(mod_a_info) do |s|
      s.execute("git checkout --detach master")
      assert File.exist?(File.join(mod_git_dir, "mod_a", "file_a.c"))
      assert File.exist?(File.join(mod_git_dir, "mod_a", "new_file.txt"))
      assert File.exist?(File.join(mod_git_dir, "mod_b", "src", "file_b.c"))
      assert s.execute("git show -s --format=%B HEAD").start_with?("Second change")
      assert s.execute("git show -s --format=%B HEAD~1").start_with?("First change")
    end
  end

  def test_files_of_new_commits_are_uploaded_to_push_branch
    mod1_info = create_module_git("mod1", "master", "for/%s")
    create_ws_git("testbr")
    sync_helper = RIM::SyncHelper.new(@ws_dir, @logger, [mod1_info])
    sync_helper.sync
    RIM::git_session(@ws_dir) do |s|
      s.execute("git rebase rim/testbr")
    end
    shas = []
    # make two changes to module
    RIM::git_session(@ws_dir) do |s|
      `echo ' appended' >> #{File.join(@ws_dir, "mod1/readme.txt")}`
      s.execute("git commit . -m \"First change\"")
      shas.push(s.rev_sha1("HEAD"))  
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Second change\"")
      shas.push(s.rev_sha1("HEAD"))  
    end
    cut = RIM::UploadHelper.new(@ws_dir, true, @logger, [mod1_info])
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout for/master")
      assert File.exist?(File.join(@remote_git_dir, "mod1/readme.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/new_file.txt"))
      assert s.execute("git show -s --format=%B HEAD").start_with?("Second change")
      assert s.execute("git show -s --format=%B HEAD~1").start_with?("First change") 
    end
  end

  def test_files_of_new_commits_are_uploaded_to_direct_branch
    mod1_info = create_module_git("mod1", "master", "for/%s")
    create_ws_git("testbr")
    sync_helper = RIM::SyncHelper.new(@ws_dir, @logger, [mod1_info])
    sync_helper.sync
    RIM::git_session(@ws_dir) do |s|
      s.execute("git rebase rim/testbr")
    end
    shas = []
    # make two changes to module
    RIM::git_session(@ws_dir) do |s|
      `echo ' appended' >> #{File.join(@ws_dir, "mod1/readme.txt")}`
      s.execute("git commit . -m \"First change\"")
      shas.push(s.rev_sha1("HEAD"))  
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Second change\"")
      shas.push(s.rev_sha1("HEAD"))  
    end
    cut = RIM::UploadHelper.new(@ws_dir, false, @logger, [mod1_info])
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout master")
      assert File.exist?(File.join(@remote_git_dir, "mod1/readme.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/new_file.txt"))
      assert s.execute("git show -s --format=%B HEAD").start_with?("Second change")
      assert s.execute("git show -s --format=%B HEAD~1").start_with?("First change") 
    end
  end
  
  def test_files_of_new_commits_are_uploaded_without_ignores
    mod1_info = create_module_git("mod1")
    create_ws_git("testbr")
    sync_helper = RIM::SyncHelper.new(@ws_dir, @logger, [mod1_info])
    sync_helper.sync
    RIM::git_session(@ws_dir) do |s|
      s.execute("git rebase rim/testbr")
    end
    shas = []
    # make two changes to module
    RIM::git_session(@ws_dir) do |s|
      `echo ' appended' >> #{File.join(@ws_dir, "mod1/readme.txt")}`
      s.execute("git commit . -m \"First change\"")
      shas.push(s.rev_sha1("HEAD"))  
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file.txt")}`
      # Adjust rim_info to contain the file as ignored file
      rim_info = RIM::RimInfo.from_dir(File.join(@ws_dir, "mod1"))
      rim_info.ignores = "new_file.txt"
      rim_info.to_dir(File.join(@ws_dir, "mod1"))
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file2.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Second change\"")
      shas.push(s.rev_sha1("HEAD"))  
    end
    cut = RIM::UploadHelper.new(@ws_dir, true, @logger, [mod1_info])
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout master")
      assert File.exist?(File.join(@remote_git_dir, "mod1/readme.txt"))
      assert !File.exist?(File.join(@remote_git_dir, "mod1/new_file.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/new_file2.txt"))
      assert s.execute("git show -s --format=%B HEAD").start_with?("Second change")
      assert s.execute("git show -s --format=%B HEAD~1").start_with?("First change")
    end
  end

  def test_files_of_amended_commits_are_uploaded
    mod1_info = create_module_git("mod1")
    create_ws_git("testbr")
    sync_helper = RIM::SyncHelper.new(@ws_dir, @logger, [mod1_info])
    sync_helper.sync
    RIM::git_session(@ws_dir) do |s|
      s.execute("git rebase rim/testbr")
    end
    shas = []
    # make two changes to module
    RIM::git_session(@ws_dir) do |s|
      `echo ' appended' >> #{File.join(@ws_dir, "mod1/readme.txt")}`
      s.execute("git commit . -m \"First change\"")
      shas.push(s.rev_sha1("HEAD"))  
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file.txt")}`
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file2.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Second change\"")
      shas.push(s.rev_sha1("HEAD"))  
    end
    cut = RIM::UploadHelper.new(@ws_dir, true, @logger, [mod1_info])
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout master")
      assert File.exist?(File.join(@remote_git_dir, "mod1/readme.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/new_file.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/new_file2.txt"))
      assert s.execute("git show -s --format=%B HEAD").start_with?("Second change")
      assert s.execute("git show -s --format=%B HEAD~1").start_with?("First change")
      s.execute("git checkout --detach master")
      s.execute("git branch -D master")
    end
    # reset testbr now on previous commit and commit new change
    RIM::git_session(@ws_dir) do |s|
      s.execute("git checkout -B testbr HEAD~1")
      `echo 'Test' > #{File.join(@ws_dir, "mod1/test_file.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Third change\"")      
    end
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout master")
      assert File.exist?(File.join(@remote_git_dir, "mod1/readme.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/test_file.txt"))
      assert !File.exist?(File.join(@remote_git_dir, "mod1/new_file.txt"))
      assert !File.exist?(File.join(@remote_git_dir, "mod1/new_file2.txt"))
      assert s.execute("git show -s --format=%B HEAD").start_with?("Third change")
      assert s.execute("git show -s --format=%B HEAD~1").start_with?("First change")
    end
  end

  def test_files_of_merged_commits_are_uploaded
    mod1_info = create_module_git("mod1")
    create_ws_git("testbr")
    sync_helper = RIM::SyncHelper.new(@ws_dir, @logger, [mod1_info])
    sync_helper.sync
    RIM::git_session(@ws_dir) do |s|
      s.execute("git rebase rim/testbr")
    end
    shas = []
    # make two changes to module
    RIM::git_session(@ws_dir) do |s|
      `echo ' appended' >> #{File.join(@ws_dir, "mod1/readme.txt")}`
      s.execute("git commit . -m \"First change\"")
      #shas.push(s.rev_sha1("HEAD"))  
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file.txt")}`
      `echo 'Test' > #{File.join(@ws_dir, "mod1/new_file2.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Second change\"")
      shas.push(s.rev_sha1("HEAD"))  
    end
    cut = RIM::UploadHelper.new(@ws_dir, true, @logger, [mod1_info])
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout --detach master")
      s.execute("git branch -D master")
    end
    # reset testbr now on previous commit and commit new change
    RIM::git_session(@ws_dir) do |s|
      s.execute("git checkout -B testbr HEAD~2")
      `echo 'Test' > #{File.join(@ws_dir, "mod1/test_file.txt")}`
      s.execute("git add .")
      s.execute("git commit . -m \"Third change\"")      
    end
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout --detach master")
      s.execute("git branch -D master")
    end
    # now merge the commits
    RIM::git_session(@ws_dir) do |s|
      s.execute("git merge #{shas[0]} --commit")
    end
    cut.upload
    module_session(mod1_info) do |s|
      s.execute("git checkout master")
      assert File.exist?(File.join(@remote_git_dir, "mod1/readme.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/new_file.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/new_file2.txt"))
      assert File.exist?(File.join(@remote_git_dir, "mod1/test_file.txt"))
      assert s.execute("git show -s --format=%B HEAD").start_with?("Merge commit")
      assert s.execute("git show -s --format=%B HEAD~1").start_with?("Third change")
    end
  end
  
private
  def create_ws_git(branch = "master")
    FileUtils.mkdir_p(@ws_remote_dir)
    RIM::git_session(@ws_remote_dir) do |s|
      s.execute("git init")
      s.execute("git checkout -B #{branch}")
      File.open(File.join(@ws_remote_dir, ".gitignore"), "w") do |f| 
        f.write(".rim") 
      end
      File.open(File.join(@ws_remote_dir, "readme"), "w") do |f|
        f.write("Content")
      end
      s.execute("git add .")
      s.execute("git commit -m \"Initial commit\"")
      s.execute("git checkout --detach #{branch}")
    end
    FileUtils.mkdir_p(@ws_dir)
    RIM::git_session(@ws_dir) do |s|
      s.execute("git clone #{@ws_remote_dir} #{@ws_dir}")
    end
  end

  def create_module_git(name, branch = "master", remote_branch_format = nil)
    git_dir = File.join(@remote_git_dir, name)
    FileUtils.mkdir_p(git_dir)
    RIM::git_session(git_dir) do |s|
      s.execute("git init")
      s.execute("git checkout -B #{branch}")
      File.open(File.join(git_dir, "readme.txt"), "w") do |f| 
        f.write("Content.") 
      end
      s.execute("git add .")
      s.execute("git commit -m \"Initial commit\"")
      s.execute("git checkout --detach #{branch}")
    end
    return RIM::ModuleInfo.new("file://" + git_dir, name, branch, nil, nil, remote_branch_format)
  end

  def create_all_module_git(name, branch = "master")
    git_dir = File.join(@remote_git_dir, name)
    FileUtils.mkdir_p(File.join(git_dir,"mod_a"))
    FileUtils.mkdir_p(File.join(git_dir,"mod_b","src"))
    RIM::git_session(git_dir) do |s|
      s.execute("git init")
      s.execute("git checkout -B #{branch}")
      File.open(File.join(git_dir, "readme.txt"), "w") do |f|
        f.write("Content.")
      end
      File.open(File.join(git_dir, "mod_a", "file_a.c"), "w") do |f|
        f.write("Content.")
      end
      File.open(File.join(git_dir, "mod_b", "src", "file_b.c"), "w") do |f|
        f.write("Content.")
      end
      s.execute("git add .")
      s.execute("git commit -m \"Initial commit\"")
      s.execute("git checkout --detach #{branch}")
    end
    return git_dir
  end


  def module_session(module_info)
    RIM::git_session(module_info.remote_url.gsub(/^file:\/\//, "")) do |s|
      yield s
    end    
  end

  def check_not_dirty(session)
    status = RIM::StatusBuilder.new.rev_status(session, "HEAD")
    status.modules.each do |m|
      assert !m.dirty?
    end    
  end
  
  def has_ancestor?(session, rev, ancestor)
    rev = session.execute("git rev-list #{rev}").include?(session.rev_sha1(ancestor))
  end
  
end
