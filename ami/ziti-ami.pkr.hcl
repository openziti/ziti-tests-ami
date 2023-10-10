packer {
  required_version = ">= 1.7.0"

  required_plugins {
    amazon = {
      version = ">= 1.2.6"
      source  = "github.com/hashicorp/amazon"
    }
  }
}

variable "elastic_version" {
  default = "7.17.5"
}

source "amazon-ebs" "ziti-tests-ubuntu-ami" {
  ami_description = "An Ubuntu AMI that has everything needed for running fablab tests."
  ami_name        = "ziti-tests-{{ timestamp }}"
  ami_regions     = ["us-east-1", "us-east-2", "us-west-1", "us-west-2", "ca-central-1", "ap-northeast-1", "ap-southeast-2", "sa-east-1", "eu-central-1", "af-south-1"]
  instance_type   = "t2.micro"
  region          = "us-east-1"
  source_ami_filter {
    filters = {
      architecture        = "x86_64"
      name                = "ubuntu/images/*/ubuntu-jammy-22.04-amd64-server-*"
      root-device-type    = "ebs"
      virtualization-type = "hvm"
    }
    most_recent = true
    owners      = ["099720109477"]
  }
  ssh_username = "ubuntu"
}

build {
  sources = ["source.amazon-ebs.ziti-tests-ubuntu-ami"]

  provisioner "file" {
    source      = "etc/apt/apt.conf.d/99remote-not-fancy"
    destination = "/home/ubuntu/99remote-not-fancy"
  }

  provisioner "file" {
    source      = "etc/sysctl.d/51-network-tuning.conf"
    destination = "/home/ubuntu/51-network-tuning.conf"
  }

  provisioner "file" {
    source      = "etc/systemd/resolved.conf.d/ziti-tunnel.conf"
    destination = "/home/ubuntu/ziti-tunnel.conf"
  }

  provisioner "file" {
    source      = "etc/log/10-ziti-logs.conf"
    destination = "/home/ubuntu/10-ziti-logs.conf"
  }

  provisioner "file" {
    source      = "etc/log/filebeat.yml"
    destination = "/home/ubuntu/filebeat.yml"
  }

  provisioner "file" {
    source      = "etc/log/metricbeat.yml"
    destination = "/home/ubuntu/metricbeat.yml"
  }

  provisioner "file" {
    source      = "/home/runner/work/ziti-tests-ami/ziti-tests-ami/beats.crt"
    destination = "/home/ubuntu/beats.crt"
  }

  provisioner "file" {
    source      = "/home/runner/work/ziti-tests-ami/ziti-tests-ami/beats.key"
    destination = "/home/ubuntu/beats.key"
  }

  provisioner "file" {
    source      = "/home/runner/work/ziti-tests-ami/ziti-tests-ami/logstashCA.crt"
    destination = "/home/ubuntu/logstashCA.crt"
  }

  provisioner "shell" {
    inline = [
      # Setup UFW to allow for blocking of 80/443 ports for test
      "sudo ufw default allow outgoing",
      "sudo ufw default allow incoming",
      "sudo ufw deny out 80/tcp",
      "sudo ufw deny out 443/tcp",
      "sudo ufw deny in 80/tcp",
      "sudo ufw deny in 443/tcp",

      # Create directories for beats/logstash certs and keys
      "sudo mkdir /etc/pki/",
      "sudo mkdir /etc/pki/beats/",

      # Set custom files with proper permissions/owners/groups
      "sudo chown root /home/ubuntu/99remote-not-fancy",
      "sudo chown :root /home/ubuntu/99remote-not-fancy",
      "sudo chown root /home/ubuntu/51-network-tuning.conf",
      "sudo chown :root /home/ubuntu/51-network-tuning.conf",
      "sudo chown root /home/ubuntu/10-ziti-logs.conf",
      "sudo chown :root /home/ubuntu/10-ziti-logs.conf",
      "sudo chown root /home/ubuntu/beats.crt",
      "sudo chown :root /home/ubuntu/beats.crt",
      "sudo chmod 0644 /home/ubuntu/beats.crt",
      "sudo chown root /home/ubuntu/beats.key",
      "sudo chown :root /home/ubuntu/beats.key",
      "sudo chmod 0400 /home/ubuntu/beats.key",
      "sudo chown root /home/ubuntu/logstashCA.crt",
      "sudo chown :root /home/ubuntu/logstashCA.crt",
      "sudo chmod 0644 /home/ubuntu/logstashCA.crt",

      # Move custom files into proper locations
      "sudo chmod 755 /etc/sysctl.d",
      "sudo mv /home/ubuntu/99remote-not-fancy /etc/apt/apt.conf.d/",
      "sudo mv /home/ubuntu/51-network-tuning.conf /etc/sysctl.d/",
      "sudo mv /home/ubuntu/10-ziti-logs.conf /etc/sysctl.d/",
      "sudo mv /home/ubuntu/beats.crt /etc/pki/beats/",
      "sudo mv /home/ubuntu/beats.key /etc/pki/beats/",
      "sudo mv /home/ubuntu/logstashCA.crt /etc/pki/beats/",

      "cloud-init status --wait",

      # Linux updates/package installs
      "sudo apt-get -qq -y update",
      "sudo apt-get -qq -y --no-install-recommends install awscli",
      "sudo apt-get -qq -y --no-install-recommends install iperf3",
      "sudo apt-get -qq -y --no-install-recommends install tcpdump",
      "sudo apt-get -qq -y --no-install-recommends install sysstat",
      "sudo apt-get -qq -y --no-install-recommends install jq",
      "sudo apt-get -qq -y --no-install-recommends upgrade",

      # Install filebeat and metricbeat
      "curl -L -O https://artifacts.elastic.co/downloads/beats/metricbeat/metricbeat-${var.elastic_version}-amd64.deb",
      "sudo dpkg -i metricbeat-${var.elastic_version}-amd64.deb",
      "curl -L -O https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-${var.elastic_version}-amd64.deb",
      "sudo dpkg -i filebeat-${var.elastic_version}-amd64.deb",

      # Consul install
      # "curl --fail --silent --show-error --location https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo dd of=/usr/share/keyrings/hashicorp-archive-keyring.gpg",
      # "echo \"deb [arch=amd64 signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main\" | sudo tee -a /etc/apt/sources.list.d/hashicorp.list",
      "sudo apt-get -qq -y install consul",

      # Set New Beats files with proper permissions
      "sudo chown root /home/ubuntu/filebeat.yml",
      "sudo chown :root /home/ubuntu/filebeat.yml",
      "sudo chown root /home/ubuntu/metricbeat.yml",
      "sudo chown :root /home/ubuntu/metricbeat.yml",

      "sudo filebeat modules enable system",
      "sudo mv /home/ubuntu/filebeat.yml /etc/filebeat/",


      "sudo mv /home/ubuntu/metricbeat.yml /etc/metricbeat/",
      "sudo systemctl enable metricbeat",
      "sudo systemctl start metricbeat",
      "sudo systemctl enable filebeat",
      "sudo systemctl start filebeat",

      "sudo bash -c \"echo 'ubuntu soft nofile 40960' >> /etc/security/limits.conf\"",
      "sudo sed -i 's/ENABLED=\"false\"/ENABLED=\"true\"/g' /etc/default/sysstat",
    ]
  }
}
