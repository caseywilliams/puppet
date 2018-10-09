test_name 'File provider: Can create directories in mounted volumes' do
  confine :to, platform: 'windows'

  # Creates a temporary VHD of minimal size, initializes it, partitions it,
  # formats it, and mounts it on the host at a temporary location.
  def create_and_mount_vhd_on(host)
    # Powershell VHD cmdlets are not available on Windows Server 2008.
    # We'll need to use a pair of diskpart script instead.

    # The first creates the disk and foramts it, then outputs a listing of
    # disks so we can get the disk number.
    # The second mounts the volume at a path (no drive letter is assigned)
    init_script = host.tmpfile("init_script")
    mount_script = host.tmpfile("mount_script")

    # diskpart wants paths to be fewer than 14 characters, so we'll use paths in C:\.
    # These paths must also use true backslashes.
    vhd_path = "C:\\disk#{rand(999999)}.vhd"

    create_remote_file(host, init_script, %Q!
      create vdisk file=#{vhd_path} maximum=4
      select vdisk file=#{vhd_path}
      attach vdisk
      convert mbr
      create partition primary
      format fs=ntfs quick
      list volume
    !)

    volume_number = nil
    on(host, "diskpart.exe /s #{init_script}") do |result|
      # `list volume` will output a table of disks with the mounted VHD annotated by a *
      volume_number = result.stdout[/\* Volume (\d+)/, 1]
      fail_test("Couldn't create and format a test VHD") unless volume_number
    end

    mount_path = "C:/mount#{rand(999999)}"
    on(host, "mkdir #{mount_path}")

    create_remote_file(host, mount_script, %Q!
      select volume #{volume_number}
      assign mount=#{mount_path.gsub('/', '\\')}
    !)

    on(host, "diskpart.exe /s #{mount_script}")

    return vhd_path, mount_path
  end

  agents.each do |agent|
    vhd_path = mount_path = nil

    teardown do
      if vhd_path
        script_path = agent.tmpfile("vhd_teardown")

        create_remote_file(agent, script_path, %Q!
          select vdisk file=#{vhd_path}
          detach vdisk
        !)

        on(agent, "diskpart.exe /s #{script_path}")
        on(agent, "rm -rf #{mount_path} #{vhd_path}")
      end
    end

    step "create an empty mounted volume" do
      vhd_path, mount_path = create_and_mount_vhd_on(agent)
    end
  end
end