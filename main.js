import { Trainer } from './js/trainer.js';
import { HeartRateMonitor } from './js/heartRateMonitor.js';
import { RampTest } from './js/ramp_test.js';
import { UI } from './js/ui.js';

const trainer = new Trainer();
const hrm = new HeartRateMonitor();
const ui = new UI();
let rampTest;
const devices = {};

document.getElementById('connect-trainer').addEventListener('click', async () => {
  await trainer.connect();
  devices.trainer = trainer.device;
  ui.updateStatus(devices);
});

document.getElementById('connect-hrm').addEventListener('click', async () => {
  await hrm.connect();
  devices.hrm = hrm.device;
  ui.updateStatus(devices);
});

document.getElementById('start-test').addEventListener('click', () => {
  const type = document.getElementById('riderType').value;
  const isHeavy = type === 'heavy';

  const warmupMin = parseInt(document.getElementById('warmupDuration').value, 10);
  const warmupSeconds = warmupMin * 60;

  const warmupWatts = parseInt(document.getElementById('warmupWatts').value, 10);

  rampTest = new RampTest(trainer, hrm, ui, isHeavy, warmupSeconds, warmupWatts);
  rampTest.start();
});

document.getElementById('restart-test').addEventListener('click', () => {
  location.reload();
});

document.getElementById('info-bubble').addEventListener('click', () => {
  alert("Heavy is 60 kg or more.");
});

document.getElementById('info-bubble-2').addEventListener('click', () => {
  alert("50% of your FTP.");
});

const riderTypeSelect = document.getElementById('riderType');
const warmupWattsInput = document.getElementById('warmupWatts');

riderTypeSelect.addEventListener('change', () => {
  const selected = riderTypeSelect.value;
  if (selected === 'light') {
    warmupWattsInput.value = 75;
  } else {
    warmupWattsInput.value = 100;
  }
});
