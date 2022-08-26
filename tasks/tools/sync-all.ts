import { task } from 'hardhat/config';

import { dreAction } from '../../helpers/dre';
import { syncAllDeployedProxies } from '../deploy/templates';

task('sync:all-proxies', 'Sync proxies listed in DeployDB').setAction(dreAction(() => syncAllDeployedProxies()));
