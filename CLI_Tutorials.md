# TDM Autopilot - Getting Started
This quickstart guide details how to start using RGSUBSET and RGANONYMIZE and see value. It explains step by step how to run the various applications straight from your preferred command-line tool such as CMD (Windows) or BASH (Linux/MacOS)

# Pre-requisites
Ensure the following tools are installed and available in your system's PATH:

- rgsubset
- rganonymize

https://documentation.red-gate.com/testdatamanager/getting-started/installation/download-links

# Database Provisioning
In order to start seeing value from rgsubset and rganonymize, it's necessary to provision two databases

- AutopilotProd_FullRestore
- Autopilot_Treated

These two databases will be used to simulate a real world scenario of obtaining a slice of data from Prod and masking it within our non-production database. In order to expedite this process and hit the ground running, it's advised to start with fictious databases. Therefore, in your TDM Autopilot folder navigate to .\Setup_Files\Sample_Database_Scripts. Within here you'll find two methods for creating the above databases in the instance of your choice:

1) Use the file 'AutopilotProd.bak' to restore two databases named as above
2) Use the scripts 'CreateAutopilotDatabaseSchemaOnly.sql' & 'CreateAutopilotDatabaseProductionData.sql' against an empty database called 'AutopilotProd_FullRestore'. Then run just 'CreateAutopilotDatabaseSchemaOnly.sql' against another empty database called 'Autopilot_Treated'

# RGSUBSET - Getting Started
Before we get started, please note that all documentation can be found here: https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/subsetting

On the command line, it's now necessary to run the command rgsubset against our target databases. To start, lets consider what parameters rgsubset needs:

--source-connection-string:
--target-connection-string:
--options-file:

rgsubset run --database-engine=sqlserver --source-connection-string="server=localhost;database=AutopilotProd_Full
Restore;Trusted_Connection=yes;TrustServerCertificate=yes;Encrypt=yes" --target-connection-string=server="localhost;
database=Autopilot_Treated;Trusted_Connection=yes;TrustServerCertificate=yes;Encrypt=yes" --target-database-write-m
ode=Overwrite --log-level=Information --options-file="C:\git\TDM-Autopilot\Setup_Files\Data_Treatments_Options_File
s\rgsubset-options-autopilot.json"

# RGANONYMIZE - Getting Started
Before we get started, please note that all documentation can be found here: https://documentation.red-gate.com/testdatamanager/command-line-interface-cli/anonymization

On the command line, it's now necessary to run the command rganonymize against our target treated databases. This section is split into three tasks: classify, map and mask.

Classify:

rganonymize classify --database-engine=sqlserver --connection-string="server=localhost;database=Autopilot_Treated
;Trusted_Connection=yes;TrustServerCertificate=yes;Encrypt=yes" --classification-file="C:\temp\tdm-autopilot\2025051
6_114921\classification.json" --output-all-columns --log-level=Information

Map:

rganonymize map --classification-file="C:\temp\tdm-autopilot\20250516_114921\classification.json" --masking-file
="C:\temp\tdm-autopilot\20250516_114921\masking.json" --log-level=Information

Mask:

rganonymize mask --database-engine=sqlserver --connection-string=server="localhost;database=Autopilot_Treated;Tru
sted_Connection=yes;TrustServerCertificate=yes;Encrypt=yes" --masking-file="C:\temp\tdm-autopilot\20250516_114921\ma
sking.json" --log-level=Information