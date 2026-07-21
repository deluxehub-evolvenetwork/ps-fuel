(() => {
  const root = document.getElementById('fuel-root');
  const app = document.getElementById('app');
  const modeLabel = document.getElementById('mode-label');
  const footerStation = document.getElementById('footer-station');
  const resource = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'ps-fuel';
  let mode = 'refuel';
  let state = {};
  let selectedFuel = null;
  let activeTab = 'overview';

  const esc = (value) => String(value ?? '').replace(/[&<>'"]/g, (c) => ({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
  const money = (value) => `£${Math.round(Number(value) || 0).toLocaleString('en-GB')}`;
  const number = (value, digits = 0) => (Number(value) || 0).toLocaleString('en-GB', {maximumFractionDigits: digits, minimumFractionDigits: digits});
  const post = async (name, data = {}) => {
    if (resource === 'ps-fuel' && typeof GetParentResourceName !== 'function') return {success:true};
    try {
      const response = await fetch(`https://${resource}/${name}`, {method:'POST', headers:{'Content-Type':'application/json; charset=UTF-8'}, body:JSON.stringify(data)});
      return await response.json();
    } catch (error) {
      return {success:false, message:'The fuel terminal could not reach the game client.'};
    }
  };
  const toast = (message, type = 'inform') => {
    if (!message) return;
    const item = document.createElement('div');
    item.className = `toast ${type}`;
    item.textContent = message;
    document.getElementById('toast-stack').appendChild(item);
    setTimeout(() => item.remove(), 3400);
  };
  const close = () => {
    root.classList.remove('visible');
    root.setAttribute('aria-hidden', 'true');
    post('fuelClose');
  };
  const fuelTypes = () => Array.isArray(state.fuelTypes) ? state.fuelTypes : [];
  const allowed = () => new Set(state.vehicle?.allowedFuelTypes || []);
  const chosen = () => fuelTypes().find((fuel) => fuel.id === selectedFuel) || fuelTypes()[0] || {unitPrice:0,label:'Fuel'};

  function pageHeader(title, description, badge = 'Online') {
    return `<div class="page-header"><div><p class="eyebrow">PS FUEL OPERATIONS</p><h1>${esc(title)}</h1><p>${esc(description)}</p></div><span class="badge">${esc(badge)}</span></div>`;
  }
  function stat(label, value, meta) {
    return `<article class="card"><div class="stat-label"><span>${esc(label)}</span><span>LIVE</span></div><div class="stat-value">${value}</div><div class="stat-meta">${esc(meta)}</div></article>`;
  }
  function tabs(items) {
    return `<nav class="tabs">${items.map(([id,label]) => `<button class="tab ${activeTab === id ? 'active' : ''}" data-tab="${id}">${label}</button>`).join('')}</nav>`;
  }

  function refuelView(includeHeader = true) {
    if (!state.vehicle) return `<article class="card empty"><div><strong>No vehicle detected</strong><p>Park beside a pump to select a fuel type.</p></div></article>`;
    const valid = fuelTypes().filter((fuel) => allowed().has(fuel.id));
    if (!selectedFuel || !allowed().has(selectedFuel)) selectedFuel = valid[0]?.id || null;
    const fuel = chosen();
    const current = Number(state.vehicle.fuel) || 0;
    return `${includeHeader ? pageHeader('Select fuel type', `${state.label || 'Fuel station'} · choose the correct fuel before using the pump`, 'Pump ready') : ''}
      <div class="fuel-layout">
        <div>
          <article class="card vehicle-card">
            <div class="vehicle-head"><div><div class="vehicle-name">${esc(state.vehicle.label)}</div><span class="vehicle-plate">${esc(state.vehicle.plate)}</span></div><span class="badge">${state.vehicle.electric ? (state.vehicle.fastCharge ? 'Fast-charge EV' : 'Electric vehicle') : (state.vehicle.diesel ? 'Diesel vehicle' : 'Petrol vehicle')}</span></div>
            <div class="gauge-row"><div class="gauge"><div class="gauge-fill" style="width:${Math.min(100,current)}%"></div></div><div class="gauge-value">${number(current,1)}%</div></div>
          </article>
          <div class="fuel-types">${fuelTypes().map((item) => {
            const enabled = allowed().has(item.id);
            return `<button class="fuel-type ${selectedFuel === item.id ? 'selected' : ''} ${enabled ? '' : 'disabled'}" data-fuel="${esc(item.id)}" ${enabled ? '' : 'disabled'} style="--fuel-accent:${esc(item.accent || '#1ee8ef')}"><strong>${esc(item.label)}</strong><small>${esc(item.description)}</small><div class="fuel-price">${money(item.unitPrice)} / 1%</div></button>`;
          }).join('')}</div>
        </div>
        <article class="card amount-panel">
          <div class="section-title"><h2>Physical pump control</h2><span>Step 1 of 2</span></div>
          <div class="summary">
            <div class="summary-row"><span>Selected fuel</span><strong>${esc(fuel.label)}</strong></div>
            <div class="summary-row"><span>${state.vehicle.electric ? 'Battery charge' : 'Current fuel'}</span><strong>${number(current,1)}%</strong></div>
            <div class="summary-row"><span>Unit rate</span><strong>${money(fuel.unitPrice)} / 1%</strong></div>
          </div>
          <p style="color:var(--muted);font-size:10px;line-height:1.7;margin:16px 0">${state.physicalNozzle ? `The connected ${state.vehicle.electric ? 'charging connector' : 'fuel nozzle'} will start automatically after selection. Live progress appears above the vehicle.` : 'Selecting a fuel type closes the terminal. Insert the nozzle into the vehicle to begin; live progress appears above it.'}</p>
          <button class="primary wide" id="select-fuel" ${!selectedFuel || current >= (Number(state.vehicle.maxFuel) || 100) ? 'disabled' : ''}>SELECT ${esc(String(fuel.label || 'FUEL').toUpperCase())}</button>
        </article>
      </div>`;
  }

  function overviewView() {
    const stockPercent = Math.min(100, ((Number(state.stock)||0) / Math.max(1,Number(state.capacity)||1))*100);
    return `${pageHeader(state.label || 'Fuel station', `Owned by ${state.owner || 'Unknown'} · management terminal`, 'Owner access')}
      ${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['ledger','Ledger']])}
      <div class="grid stats">${stat('Station balance', money(state.balance), 'Available to withdraw')}${stat('Lifetime revenue', money(state.totalSales), 'Gross station sales')}${stat('Fuel sold', `${number(state.totalFuel,1)}%`, 'Recorded volume')}${stat('Price multiplier', `${number(state.priceMultiplier || 1,2)}×`, 'Owner retail rate')}</div>
      <div class="grid two" style="margin-top:12px"><article class="card"><div class="section-title"><h2>Fuel reserves</h2><span>${number(stockPercent,0)}% capacity</span></div><div class="gauge"><div class="gauge-fill" style="width:${stockPercent}%"></div></div><div class="summary-row"><span>Current stock</span><strong>${number(state.stock,0)} / ${number(state.capacity,0)}</strong></div><div class="summary-row"><span>Market multiplier</span><strong>${number(state.marketMultiplier || 1,2)}×</strong></div></article><article class="card"><div class="section-title"><h2>Owner controls</h2><span>Protected</span></div><p style="color:var(--muted);font-size:10px;line-height:1.6">Only the station owner or an authorised administrator can open this management tablet. Public players retain access to the pump terminal only.</p><button class="secondary wide" id="refresh-station">Synchronise station data</button></article></div>`;
  }

  function operationsView() {
    return `${pageHeader(state.label || 'Fuel station','Pricing, banking and station operations','Owner controls')}${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['ledger','Ledger']])}<div class="grid two"><article class="card"><div class="section-title"><h2>Retail pricing</h2><span>0.50× – 2.00×</span></div><label class="form-label" for="multiplier">Station price multiplier</label><input class="text-input" id="multiplier" type="number" min="0.5" max="2" step="0.05" value="${Number(state.priceMultiplier)||1}"/><button class="primary wide" id="save-multiplier">Save pricing</button><button class="secondary wide" id="withdraw">Withdraw ${money(state.balance)}</button></article><article class="card"><div class="section-title"><h2>Station services</h2><span>Live actions</span></div><div class="action-list"><div class="action"><div class="action-copy"><strong>Fuel delivery</strong><small>Collect a tanker and replenish station stock.</small></div><button class="secondary" id="start-delivery" ${state.deliveriesEnabled ? '' : 'disabled'}>Start</button></div><div class="action"><div class="action-copy"><strong>Jerry can</strong><small>Purchase portable emergency fuel for ${money(state.jerryCanPrice)}.</small></div><button class="secondary" id="buy-jerry">Buy</button></div><div class="action"><div class="action-copy"><strong>Security simulation</strong><small>Start the configured station robbery flow.</small></div><button class="danger" id="start-robbery" ${state.robberiesEnabled ? '' : 'disabled'}>Start</button></div></div></article></div>`;
  }

  function ledgerView() {
    const rows = Array.isArray(state.transactions) ? state.transactions : [];
    return `${pageHeader(state.label || 'Fuel station','Latest station transactions and operational records','Live ledger')}${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['ledger','Ledger']])}<article class="card"><div class="section-title"><h2>Recent transactions</h2><span>${rows.length} records</span></div><div class="transactions">${rows.length ? rows.map((row) => `<div class="transaction"><div><strong>${esc(String(row.transaction_type || 'transaction').replaceAll('_',' ').toUpperCase())}</strong><small>${esc(row.player_name || 'System')} · ${esc(row.created_at || '')}</small></div><span>${number(row.fuel_amount,1)}%</span><span class="amount">${money(row.amount_paid)}</span></div>`).join('') : '<div class="empty">No transactions have been recorded.</div>'}</div></article>`;
  }

  function adminView() {
    const totals = state.totals || {};
    const stations = Array.isArray(state.stations) ? state.stations : [];
    return `${pageHeader('Fuel network administration','Read-only operational overview across every configured station','Admin link')}<div class="grid stats">${stat('Transactions', number(totals.transactions), 'Network records')}${stat('Revenue', money(totals.revenue), 'Gross network sales')}${stat('Fuel moved', `${number(totals.fuel,1)}%`, 'Recorded volume')}${stat('Stations', number(stations.length), 'Configured locations')}</div><article class="card" style="margin-top:12px"><table class="station-table"><thead><tr><th>Station</th><th>Owner</th><th>Revenue</th><th>Stock</th><th>Price</th></tr></thead><tbody>${stations.map((station)=>`<tr><td>${esc(station.label)}</td><td>${esc(station.owner || 'Unowned')}</td><td>${money(station.totalSales)}</td><td>${number(station.stock,0)} / ${number(station.capacity,0)}</td><td>${number(station.priceMultiplier,2)}×</td></tr>`).join('')}</tbody></table></article>`;
  }

  function render() {
    modeLabel.textContent = mode === 'admin' ? 'Network administration' : mode === 'station' ? 'Owner management tablet' : 'Fuel type selector';
    footerStation.textContent = state.label ? String(state.label).toUpperCase() : 'CONNECTED';
    if (mode === 'admin') app.innerHTML = adminView();
    else if (mode === 'refuel') app.innerHTML = refuelView(true);
    else if (activeTab === 'refuel') app.innerHTML = `${pageHeader(state.label || 'Fuel station','Select a compatible fuel type, then use the physical pump','Fuel selector')}${tabs([['overview','Overview'],['refuel','Refuel'],['operations','Operations'],['ledger','Ledger']])}${refuelView(false)}`;
    else if (activeTab === 'operations') app.innerHTML = operationsView();
    else if (activeTab === 'ledger') app.innerHTML = ledgerView();
    else app.innerHTML = overviewView();
    bind();
  }

  function bind() {
    app.querySelectorAll('[data-tab]').forEach((button) => button.addEventListener('click', () => {activeTab = button.dataset.tab; render();}));
    app.querySelectorAll('[data-fuel]').forEach((button) => button.addEventListener('click', () => {selectedFuel = button.dataset.fuel; render();}));
    document.getElementById('select-fuel')?.addEventListener('click', async (event) => {
      event.currentTarget.disabled = true;
      event.currentTarget.textContent = 'SELECTING…';
      const response = await post('selectFuelType',{stationId:state.id,fuelType:selectedFuel});
      if (response?.success) {
        event.currentTarget.textContent = `${String(response.fuelLabel || 'FUEL').toUpperCase()} SELECTED`;
        toast(response.message || 'Fuel type selected.','success');
      } else {
        toast(response?.message || 'Fuel selection failed.','error');
        render();
      }
    });
    document.getElementById('refresh-station')?.addEventListener('click', refreshStation);
    document.getElementById('save-multiplier')?.addEventListener('click', async () => {const response=await post('setMultiplier',{stationId:state.id,multiplier:Number(document.getElementById('multiplier').value)});toast(response?.message || (response?.success?'Pricing updated.':'Pricing update failed.'),response?.success?'success':'error');if(response?.success) refreshStation();});
    document.getElementById('withdraw')?.addEventListener('click', async () => {const response=await post('withdraw',{stationId:state.id});toast(response?.message || (response?.success?`Withdrew ${money(response.amount)}.`:'Withdrawal failed.'),response?.success?'success':'error');if(response?.success) refreshStation();});
    document.getElementById('buy-jerry')?.addEventListener('click', async () => {const response=await post('buyJerryCan',{stationId:state.id});toast(response?.message || (response?.success?'Jerry can purchased.':'Purchase failed.'),response?.success?'success':'error');});
    document.getElementById('start-delivery')?.addEventListener('click', async () => {const response=await post('startDelivery',{stationId:state.id});toast(response?.message || (response?.success?'Delivery started.':'Delivery failed.'),response?.success?'success':'error');});
    document.getElementById('start-robbery')?.addEventListener('click', async () => {const response=await post('startRobbery',{stationId:state.id});toast(response?.message || (response?.success?'Security event started.':'Action failed.'),response?.success?'success':'error');});
  }
  async function refreshStation(){const response=await post('refreshStation',{stationId:state.id});if(response?.success&&response.data){const vehicle=state.vehicle;state=response.data;if(vehicle)state.vehicle=vehicle;toast('Station data synchronised.','success');render();}else toast(response?.message||'Refresh failed.','error');}
  function open(payload){mode=payload.mode||'refuel';state=payload.data||{};activeTab='overview';const valid=fuelTypes().filter((fuel)=>(state.vehicle?.allowedFuelTypes||[]).includes(fuel.id));selectedFuel=valid[0]?.id||null;root.classList.add('visible');root.setAttribute('aria-hidden','false');render();}
  window.addEventListener('message',(event)=>{const message=event.data||{};if(message.action==='open')open(message);if(message.action==='reset'){root.classList.remove('visible');root.setAttribute('aria-hidden','true');}});
  document.getElementById('close-button').addEventListener('click',close);
  document.addEventListener('keydown',(event)=>{if(event.key==='Escape')close();});
  setInterval(()=>{document.getElementById('clock').textContent=new Date().toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'});},1000);
  document.getElementById('clock').textContent=new Date().toLocaleTimeString('en-GB',{hour:'2-digit',minute:'2-digit'});

  if (typeof GetParentResourceName !== 'function') {
    open({mode:'station',data:{id:'strawberry',label:'Strawberry Fuel',owner:'Techy',balance:18420,totalSales:78350,totalFuel:12642,priceMultiplier:1.05,stock:7420,capacity:10000,marketMultiplier:.96,jerryCanPrice:350,deliveriesEnabled:true,robberiesEnabled:true,vehicle:{label:'Benefactor Schafter V12',plate:'SARP 26',fuel:37.4,maxFuel:100,diesel:false,allowedFuelTypes:['petrol','premium']},fuelTypes:[{id:'petrol',label:'Petrol',description:'Regular unleaded for standard road vehicles.',unitPrice:1.92,accent:'#1ee8ef'},{id:'premium',label:'Premium',description:'High-octane unleaded for performance vehicles.',unitPrice:2.59,accent:'#a78bfa'},{id:'diesel',label:'Diesel',description:'Commercial diesel for configured heavy vehicles.',unitPrice:2.15,accent:'#f6b84c'}],transactions:[{transaction_type:'fuel_premium',player_name:'Alex Morgan',amount_paid:126,fuel_amount:48,created_at:'Today 00:41'},{transaction_type:'fuel_petrol',player_name:'Jamie Clark',amount_paid:82,fuel_amount:41,created_at:'Today 00:36'}]}});
  }
})();
