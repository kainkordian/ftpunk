export class HeartRateMonitor {
  constructor() {
    this.heartRate = 0;
    this.device = null;
  }

  async connect() {
    const device = await navigator.bluetooth.requestDevice({
      filters: [{ services: ['heart_rate'] }]
    });
    this.device = device;

    const server = await device.gatt.connect();
    const service = await server.getPrimaryService('heart_rate');
    const char = await service.getCharacteristic('heart_rate_measurement');

    await char.startNotifications();
    char.addEventListener('characteristicvaluechanged', this._handleHR.bind(this));
  }

  _handleHR(event) {
    const value = event.target.value;
    const flags = value.getUint8(0);
    this.heartRate = flags & 0x01 ? value.getUint16(1, true) : value.getUint8(1);
    document.getElementById('hr').textContent = this.heartRate + " BPM";
  }
}
