# UiPath Robot

This template creates a Virtual Machine (VM) in a resource group, then deploy **UiPath Robot**.
Based on the Virtual Machine (VM) name, following components are created : </br> 
    -VM network interface (vmname-nic), </br> 
    -Network security group (vmname-nsg with following open ports : 80,443 and 3389),</br> 
    -Virtual network (vmname-vnet).</br> 
	-Public IP
	

[![Deploy to Azure](https://azuredeploy.net/deploybutton.png)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhteo1337%2FUiRobot%2Fmaster%2Fvmcount-unattended.json)



Deploy to Azure on same virtual network and network security group , with continous itineration from existing vms.
[![Deploy to Azure](https://azuredeploy.net/deploybutton.png)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fhteo1337%2FUiRobot%2Fmaster%2Fvmcount-continue.json)
