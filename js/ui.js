export class UI {
  update(power, cadence, speed, hr, elapsed, target) {
    document.getElementById('power').textContent = power + " W";
    document.getElementById('target').textContent = target + " W";
    console.log(target);
    document.getElementById('cadence').textContent = cadence + " RPM";
    // document.getElementById('speed').textContent = speed.toFixed(1);
    // document.getElementById('hr').textContent = hr + " BPM";
    document.getElementById('time').textContent = this._formatTime(elapsed);
  }

  updateStatus(devices = {}) {
    const statusDiv = document.getElementById('status');
    const startBtn = document.getElementById('start-test');
    let html = '';

    const trainerConnected = !!devices.trainer;
    const hrmConnected = !!devices.hrm;

    if (trainerConnected) {
      html += `<p>🚴 Trainer connected: <strong>${devices.trainer.name}</strong></p>`;
    } else {
      html += `<p>🚴 Trainer not connected</p>`;
    }

    if (hrmConnected) {
      html += `<p>❤️ Heart Rate Monitor connected: <strong>${devices.hrm.name}</strong></p>`;
    } else {
      html += `<p>❤️ Heart Rate Monitor not connected</p>`;
    }

    statusDiv.innerHTML = html;

    // Enable the Start Test button only when both devices are connected
    // startBtn.disabled = !(trainerConnected && hrmConnected);
    startBtn.disabled = !(trainerConnected);
  }


  showMessage(msg) {
    const ftpBox = document.getElementById('status');
    ftpBox.textContent = msg;
  }

  showFTP(min, max, avg) {
    const ftpBox = document.getElementById('status');
    ftpBox.innerHTML = `
      <div class="ftp-result">
        🚀 <strong>Estimated FTP:</strong><br>
        <span>${min} – ${max} W</span><br>
        <span>Averaged ${avg} W in the last minute.</span>
      </div>
    `;
  }


  setBackground(state) {
    if (state === 'done') {
      document.body.classList.add('done');
    } else {
      document.body.classList.remove('done');
    }
  }

  showRestart() {
    document.getElementById('restart-test').style.display = 'inline-block';
  }

  _formatTime(sec) {
    const m = Math.floor(sec / 60);
    const s = sec % 60;
    return `${m}:${s.toString().padStart(2, '0')}`;
  }
}
