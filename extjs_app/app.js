Ext.application({
    name: 'HydroValley',
    launch: function () {
        var me = this;

        // --- Constants ---
        var JULIA_SIMULATION_URL = "http://127.0.0.1:8081/run_simulation";
        var JULIA_LAYOUT_URL = "http://127.0.0.1:8081/calculate_layout";

        // --- Main Viewport ---
        Ext.create('Ext.container.Viewport', {
            layout: 'fit',
            items: [
                {
                    xtype: 'tabpanel',
                    id: 'main-tabs',
                    items: [
                        // --- Editor Tab ---
                        {
                            title: 'Editor',
                            layout: {
                                type: 'hbox',
                                align: 'stretch'
                            },
                            items: [
                                // --- JSON Editor Panel ---
                                {
                                    xtype: 'panel',
                                    title: 'Valley Definition (JSON)',
                                    layout: 'fit',
                                    flex: 1,
                                    items: [
                                        {
                                            xtype: 'textarea',
                                            id: 'json-editor',
                                            autoScroll: true,
                                            listeners: {
                                                change: {
                                                    fn: function() {
                                                        me.updateGraph();
                                                    },
                                                    buffer: 500 // Debounce requests
                                                }
                                            }
                                        }
                                    ],
                                    bbar: [
                                        '->', // Right-align button
                                        {
                                            xtype: 'button',
                                            text: 'Run Simulation',
                                            handler: function() {
                                                me.runSimulation();
                                            }
                                        }
                                    ]
                                },
                                // --- Graph Panel ---
                                {
                                    xtype: 'panel',
                                    title: 'Valley Network Graph',
                                    flex: 1.5,
                                    html: '<div id="network-graph" style="width: 100%; height: 100%;"></div>',
                                    listeners: {
                                        afterrender: function() {
                                            // Initialize graphviz after the panel is rendered
                                            me.initializeGraph();
                                        }
                                    }
                                }
                            ]
                        },
                        // --- Simulation Results Tab ---
                        {
                            title: 'Simulation Results',
                            id: 'results-tab',
                            layout: 'fit',
                            items: [
                                {
                                    xtype: 'panel',
                                    id: 'results-panel',
                                    html: '<div style="padding: 10px;">Click \'Run Simulation\' in the \'Editor\' tab to see results here.</div>'
                                }
                            ]
                        }
                    ]
                }
            ]
        });

        // --- Load Initial Data ---
        me.loadDefaultData();
    },

    // --- Graph Logic ---
    initializeGraph: function() {
        var me = this;
        me.graphviz = d3.select("#network-graph").graphviz({
            useWorker: false,
            width: "100%",
            height: "100%",
            fit: true
        });
    },

    updateGraph: function() {
        var me = this;
        var jsonText = Ext.getCmp('json-editor').getValue();
        try {
            // Validate JSON before sending
            JSON.parse(jsonText);
        } catch (e) {
            // Maybe show an error in the UI
            console.log("Invalid JSON, not updating graph.");
            return;
        }

        Ext.Ajax.request({
            url: "http://127.0.0.1:8081/calculate_layout",
            method: 'POST',
            jsonData: Ext.decode(jsonText),
            success: function (response) {
                var dotString = response.responseText;
                if (me.graphviz) {
                    me.graphviz.renderDot(dotString);
                }
            },
            failure: function (response) {
                Ext.Msg.alert('Error', 'Failed to connect to the Julia server for layout calculation.');
            }
        });
    },

    // --- Simulation Logic ---
    runSimulation: function() {
        var me = this;
        var jsonText = Ext.getCmp('json-editor').getValue();

        try {
            JSON.parse(jsonText);
        } catch (e) {
            Ext.Msg.alert('Error', 'Invalid JSON format. Cannot run simulation.');
            return;
        }

        var resultsTab = Ext.getCmp('results-tab');
        Ext.getCmp('main-tabs').setActiveTab(resultsTab);
        resultsTab.setLoading('Running simulation...');

        Ext.Ajax.request({
            url: "http://127.0.0.1:8081/run_simulation",
            method: 'POST',
            jsonData: Ext.decode(jsonText),
            timeout: 30000, // 30 seconds
            success: function (response) {
                resultsTab.setLoading(false);
                var responseData = Ext.decode(response.responseText);
                me.displayResults(responseData.volume_history);
            },
            failure: function (response) {
                resultsTab.setLoading(false);
                Ext.Msg.alert('Error', 'Failed to connect to the Julia server for simulation.');
            }
        });
    },

    // --- Data Loading ---
    loadDefaultData: function() {
        var me = this;
        Ext.Ajax.request({
            url: 'datasets/hydro_valley_instance.json',
            success: function(response, opts) {
                var defaultData = Ext.decode(response.responseText);
                var formattedJson = JSON.stringify(defaultData, null, 2);
                Ext.getCmp('json-editor').setValue(formattedJson);
                // The change listener will trigger the initial graph update
            },
            failure: function(response, opts) {
                Ext.Msg.alert('Error', 'Could not load default dataset.');
            }
        });
    },

    // --- Results Display ---
    displayResults: function(volumeHistory) {
        var resultsPanel = Ext.getCmp('results-panel');

        // Prepare data for the chart
        var fields = ['timestep'];
        var data = [];
        var reservoirNames = Object.keys(volumeHistory);
        reservoirNames.forEach(function(name) {
            fields.push(name);
        });

        var numTimesteps = volumeHistory[reservoirNames[0]].length;
        for (var i = 0; i < numTimesteps; i++) {
            var record = { timestep: i };
            reservoirNames.forEach(function(name) {
                record[name] = volumeHistory[name][i];
            });
            data.push(record);
        }

        var store = Ext.create('Ext.data.Store', {
            fields: fields,
            data: data
        });

        // Create the chart
        var chart = Ext.create('Ext.chart.CartesianChart', {
            store: store,
            insetPadding: 20,
            axes: [{
                type: 'numeric',
                position: 'left',
                title: 'Volume (M m^3)',
                grid: true,
                minimum: 0
            }, {
                type: 'category',
                position: 'bottom',
                title: 'Time Step',
                fields: ['timestep']
            }],
            series: reservoirNames.map(function(name) {
                return {
                    type: 'line',
                    xField: 'timestep',
                    yField: name,
                    tooltip: {
                        trackMouse: true,
                        renderer: function (tooltip, record, item) {
                            tooltip.setHtml(item.series.getYField() + ': ' + record.get(item.series.getYField()));
                        }
                    }
                };
            }),
            legend: {
                docked: 'right'
            }
        });

        resultsPanel.removeAll();
        resultsPanel.add(chart);
    }
});
