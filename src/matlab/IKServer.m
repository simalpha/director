classdef IKServer

    properties
        robot
        ikoptions
        q_nom
    end

    methods

        function obj = IKServer()

            options.floating = true;
            options.ignore_terrain_collisions = true;
            options.terrain = [];

            obj.robot = RigidBodyManipulator('', options);
        end

        function obj = loadNominalData(obj,filename)
            if nargin < 1 
                filename = [getenv('DRC_BASE'), ...
                            '/software/control/matlab/data/atlas_bdi_fp.mat']; 
            end
            %nom_data = load([getDrakePath() '/examples/Atlas/data/atlas_bdi_fp.mat']);
            nom_data = load(filename);
            nq = obj.robot.getNumPositions();
            obj.q_nom = nom_data.xstar(1:nq);
        end

        function obj = setupCosts(obj)

            obj.ikoptions = IKoptions(obj.robot);
            obj.ikoptions = obj.ikoptions.setMajorIterationsLimit(500);
            obj.ikoptions = obj.ikoptions.setMex(true);
            % obj.ikoptions = obj.ikoptions.setDebug(true);

            leftLegCost = 1e3;
            rightLegCost = 1e3;
            leftArmCost = 1;
            rightArmCost = 1;
            backCost = 1e4;
            neckCost = 1e6;

            nq = obj.robot.getNumPositions();

            cost = Point(obj.robot.getStateFrame(), 1);

            cost.base_x = 0;
            cost.base_y = 0;
            cost.base_z = 0;
            cost.base_roll = 1e3;
            cost.base_pitch = 1e3;
            cost.base_yaw = 0;

            cost.back_bkz = backCost;
            cost.back_bky = backCost;
            cost.back_bkx = backCost;

            cost.neck_ay =  neckCost;

            cost = double(cost);

            l_arm_indices = findPositionIndices(obj.robot, 'l_arm');
            cost(l_arm_indices) = leftArmCost;

            r_arm_indices = findPositionIndices(obj.robot, 'r_arm');
            cost(r_arm_indices) = rightArmCost;

            l_leg_indices = findPositionIndices(obj.robot, 'l_leg');
            cost(l_leg_indices) = leftLegCost;

            r_leg_indices = findPositionIndices(obj.robot, 'r_leg');
            cost(r_leg_indices) = rightLegCost;

            vel_cost = cost*0.05;
            accel_cost = cost*0.05;

            obj.ikoptions = obj.ikoptions.setQ(diag(cost(1:nq)));
            obj.ikoptions = obj.ikoptions.setQa(diag(vel_cost(1:nq)));
            obj.ikoptions = obj.ikoptions.setQv(diag(accel_cost(1:nq)));
            obj.ikoptions = obj.ikoptions.setqd0(zeros(nq,1), zeros(nq,1)); % upper and lower bnd on initial velocity.
            obj.ikoptions = obj.ikoptions.setqdf(zeros(nq,1), zeros(nq,1)); % upper and lower bnd on final velocity.

        end


        function obj = addRobot(obj, filename)

            options.floating = true;
            options.ignore_terrain_collisions = true;
            options.terrain = [];

            xyz = zeros(3,1);
            rpy = zeros(3,1);
            obj.robot = obj.robot.addRobotFromURDF(filename , xyz, rpy, options);
            %obj.robot = weldFingerJoints(obj.robot);
            obj.robot = compile(obj.robot);

        end


        function obj = addAffordance(obj, affordanceName)
            filename = [getenv('DRC_PATH'), '/drake/systems/plants/test/', affordanceName, '.urdf'];
            options = struct('floating', false);
            xyz = zeros(3,1);
            rpy = zeros(3,1);
            obj.robot = obj.robot.addRobotFromURDF(filename , xyz, rpy, options);
            obj.robot = compile(obj.robot);
        end

        function linkNames = getLinkNames(obj)
            linkNames = {obj.robot.body.linkname}';
        end

        function pts = getLeftFootPoints(obj)
            bodyIndex = obj.robot.findLinkId('l_foot');
            pts = obj.robot.body(bodyIndex).getTerrainContactPoints();
        end

        function pts = getRightFootPoints(obj)
            bodyIndex = obj.robot.findLinkId('r_foot');
            pts = obj.robot.body(bodyIndex).getTerrainContactPoints();
        end


        function plan_time = getPlanTimeForJointVelocity(obj, xtraj, maxDegreesPerSecond)

            qdot_desired = maxDegreesPerSecond*pi/180;

            nq = obj.robot.getNumPositions();
            ts = xtraj.pp.breaks;

            sfine = linspace(ts(1), ts(end), 50);
            coords = obj.robot.getStateFrame.coordinates(1:nq);
            neck_idx = strcmp(coords, 'neck_ay');
            back_joints = cellfun(@(s) ~isempty(strfind(s,'back_bk')), coords);

            qtraj = xtraj(1:nq);
            dqtraj = fnder(qtraj, 1);
            qdot_breaks = dqtraj.eval(sfine);
            weighted_qdot_breaks = qdot_breaks(~neck_idx,:);
            weighted_qdot_breaks(back_joints,:) = 2*weighted_qdot_breaks(back_joints,:);
            plan_time = max(max(abs(weighted_qdot_breaks),[],2))/qdot_desired;

        end

        function publishTraj(obj, plan_pub, atlas, xtraj, snopt_info, timeInSeconds)

            for i = 1:atlas.getNumStates
                atlas2robotFrameIndMap(i) = find(strcmp(atlas.getStateFrame.coordinates{i}, obj.robot.getStateFrame.coordinates));
            end

            utime = now() * 24 * 60 * 60;
            nq_atlas = length(atlas2robotFrameIndMap)/2;
            ts = xtraj.pp.breaks;
            q = xtraj.eval(ts);
            xtraj_atlas = zeros(2+2*nq_atlas,length(ts));
            xtraj_atlas(2+(1:nq_atlas),:) = q(atlas2robotFrameIndMap(1:nq_atlas),:);
            snopt_info_vector = snopt_info*ones(1, size(xtraj_atlas,2));

            ts = ts*timeInSeconds;
            ts = ts - ts(1);
            plan_pub.publish(xtraj_atlas, ts, utime, snopt_info_vector);

        end

    end

end
