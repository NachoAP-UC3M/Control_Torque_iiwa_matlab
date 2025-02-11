%% Aclaración %%
%
% SE ACONSEJA ENTENDER EL ARCHIVO: "LBRTorqueControlExample.m " 
% ya que este es simplemente una modificación del archivo base "LBRTorqueControlExample.m " 

%% Bibliografía 
%
% Se ha tomado como base el código que viene en la siguiente página:
% https://www.mathworks.com/help/robotics/examples/control-lbr-manipulator-motion-through-joint-torque.html
%
% PAPER: "Improving the Inverse Dynamics Model of the KUKA LWR IV+ using 
% Independent Joint Learning"

%% Esencial para que funcione %%

% Click derecho en la carpeta: functions_created_by_myself
% seleccionar: Add to Path > Selected Folders and subfolders

%% Código

clear all;close all;
% Cargamos el modelo del robot
lbr = importrobot('iiwa14.urdf');
lbr.DataFormat = 'row';

% Set the gravity to be the same as that in Gazebo.
lbr.Gravity = [0 0 -9.80];

% Pre-Compute Joint Torque Trajectory for Desired Motion

% Load joint configuration waypoints. This gives the key frames for the 
% desired motion of the robot.

%%% load lbr_waypoints.mat

% It chose and create one of nine trayectories from paper: "Improving the Inverse
% Dynamics Model of the KUKA LWR IV+ using Independent Joint Learning"

trayectoria = 1;
[tWaypoints,qWaypoints] = TrayectoryGenerator_IJLDataAdquisition(trayectoria);

% PARTE REPRESENTAR

lbr.Bodies{1,2}.Joint.HomePosition = qWaypoints(1,1);
lbr.Bodies{1,3}.Joint.HomePosition = qWaypoints(1,2);
lbr.Bodies{1,4}.Joint.HomePosition = qWaypoints(1,3);
lbr.Bodies{1,5}.Joint.HomePosition = qWaypoints(1,4);
lbr.Bodies{1,6}.Joint.HomePosition = qWaypoints(1,5);
lbr.Bodies{1,7}.Joint.HomePosition = qWaypoints(1,6);
lbr.Bodies{1,8}.Joint.HomePosition = qWaypoints(1,7);


% Show home configuration in a MATLAB figure.
figure; hold on;
show(lbr);

lbr.Bodies{1,2}.Joint.HomePosition = qWaypoints(end,1);
lbr.Bodies{1,3}.Joint.HomePosition = qWaypoints(end,2);
lbr.Bodies{1,4}.Joint.HomePosition = qWaypoints(end,3);
lbr.Bodies{1,5}.Joint.HomePosition = qWaypoints(end,4);
lbr.Bodies{1,6}.Joint.HomePosition = qWaypoints(end,5);
lbr.Bodies{1,7}.Joint.HomePosition = qWaypoints(end,6);
lbr.Bodies{1,8}.Joint.HomePosition = qWaypoints(end,7);

show(lbr);
view([150 12]);
axis([-0.8 0.8 -0.8 0.8 0 1.35]);
camva(9);
daspect([1 1 1]);


%   qWaypoints =    [0 0 0 0 0 0 0;
%                    qWaypoints(1,:)
%                     qWaypoints(end,:)];
% 
%   tWaypoints = [0,1,3];

% If trayectory doesn't start in homeposition ( articular position 
% q = [0 0 0 0 0 0 0] ) it create a new trayectory adding the start in the
% homeposition

[tWaypoints,qWaypoints] = redireccionarInicioTrayectoria(tWaypoints,qWaypoints);

%%% TRAYECTORIA CREADA MANUALMENTE

% INICIAR A CERO para que calcule los esfuerzos correctamente

lbr.Bodies{1,2}.Joint.HomePosition = 0;
lbr.Bodies{1,3}.Joint.HomePosition = 0;
lbr.Bodies{1,4}.Joint.HomePosition = 0;
lbr.Bodies{1,5}.Joint.HomePosition = 0;
lbr.Bodies{1,6}.Joint.HomePosition = 0;
lbr.Bodies{1,7}.Joint.HomePosition = 0;
lbr.Bodies{1,8}.Joint.HomePosition = 0;

%%% [qWaypoints,tWaypoints] = generador_trayectoriaOficial();
% cdt is the planned control stepsize. We use it to populate a set of time 
% points where the trajectory needs to be evaluated and store it in vector
tt_final = tWaypoints(end);
cdt = 0.001; 
tt = 0:cdt:tt_final;

% Generate desired motion trajectory for each joint.
% exampleHelperJointTrajectoryGeneration generates joint trajectories from 
% given time and joint configuration waypoints. 
% The trajectories are generated using pchip so that the interpolated 
% joint position does not violate joint limits as long as the waypoints do not.
[qDesired, qdotDesired, qddotDesired, tt] = exampleHelperJointTrajectoryGeneration(tWaypoints, qWaypoints, tt);

% Pre-compute feed-forward torques that ideally would realize the desired motion (assuming no disturbances or any kind of errors)
% using inverseDynamics. The following for loop takes some time to run. 
% To accelerate, consider used generated code for inverseDynamics. 
% See the last section for details on how to do it.
n = size(qDesired,1);
tauFeedForward = zeros(n,7);
for i = 1:n
    tauFeedForward(i,:) = inverseDynamics(lbr, qDesired(i,:), qdotDesired(i,:), qddotDesired(i,:));
end


% COMPROBACION TRAYECTORIA, TORQUE CALCULADO
for i=1:7
    figure; hold on;
    plot(tWaypoints,qWaypoints(:,i),'b')
    plot(tt,qDesired(:,i),'r')
end

for i=1:7
    figure;
    plot(tt,tauFeedForward(:,i))
end

% save('Trayectoria1_PaperIJL.mat','tt','qDesired','qdotDesired','qddotDesired','tauFeedForward')
%%
rosshutdown;
init_sin_iiwa();

[jointTorquePub, jtMsg] = rospublisher('/iiwa_gazebo_plugin/joint_command');
jointStateSub = rossubscriber('/iiwa_gazebo_plugin/joint_state');

mdlConfigClient = rossvcclient('gazebo/set_model_configuration');

msg = rosmessage(mdlConfigClient);
msg.ModelName = 'mw_iiwa';
msg.UrdfParamName = 'robot_description';
msg.JointNames = {'mw_iiwa_joint_1', 'mw_iiwa_joint_2', 'mw_iiwa_joint_3',...
                  'mw_iiwa_joint_4', 'mw_iiwa_joint_5', 'mw_iiwa_joint_6', 'mw_iiwa_joint_7'};
msg.JointPositions = homeConfiguration(lbr);

% Computed Torque Control

% Specify PD gains.
weights = [0.3,0.8,0.6,0.6,0.3,0.2,0.1];
Kp = 100*weights;
Kd = 2* weights;

once = 1;

% Prepare for data logging.
feedForwardTorque = zeros(n, 7);
pdTorque = zeros(n, 7);
timePoints = zeros(n,1);
Q = zeros(n,7);
QDesired = zeros(n,7);
call(mdlConfigClient, msg)
% Computed torque control is implemented in the for loop below. As soon as
% MATLAB receives a new joint state from Gazebo, it looks up in the 
% pre-generated tauFeedForward and finds the feed-forward torque 
% corresponding to the time stamp. It also computes a PD torque to 
% compensate for the errors in joint position and velocities [1].

% With default settings in Gazebo, the /iiwa_matlab_plugin/iiwa_matlab_joint_state
%  topic is updated at around 1 kHz (Gazebo sim time) with a typical 0.6 
% real time factor. And the torque control loop below can typically run 
% at around 200 Hz (Gazebo sim time).
clear torques_commanded
clear torques_read
clear t_measured
clear Q
for i = 1:n
    % Get joint state from Gazebo.
    jsMsg = receive(jointStateSub);

    q = jsMsg.Position';
    qdot=jsMsg.Velocity';
    qtorque=jsMsg.Effort';
    
    tiempo_sec=jsMsg.Header.Stamp.Sec;
    tiempo_nsec=jsMsg.Header.Stamp.Nsec;
    tiempo_actual = jsMsg.Header.Stamp.Sec + (jsMsg.Header.Stamp.Nsec/1000000000);
    
    t=jsMsg.Header.Stamp.seconds;
    
    % Set the start time.
    if once
        t_measured_init = tiempo_actual;
        tStart = tiempo_actual;
        once = 0;
    end
    
    % Find the corresponding index h in tauFeedForward vector for joint 
    % state time stamp t.
    h = ceil((t - tStart + 1e-8)/cdt);
    if h>n
        break
    end
    
    % Inquire feed-forward torque at the time when the joint state is
    % updated (Gazebo sim time).
    tau1 = tauFeedForward(h,:);
    % Log feed-forward torque.
    feedForwardTorque(i,:) = tau1;
    
    % Compute PD compensation torque based on joint position and velocity
    % errors.
    tau2 = Kp.*(qDesired(h,:) - q) + Kd.*(qdotDesired(h,:) - qdot);
    % Log PD torque.
    pdTorque(i,:) = tau2';
    
    % Combine the two torques.
    tau = tau1 + tau2;
    
    % Log the time.
    timePoints(i) = tiempo_actual;
    
    % Send torque to Gazebo.
    jtMsg.Effort = tau;
    
    %%% INPUT DATA %%%
    % Log joint positions data.
    Q(i,:) = q';
    N_QDesired(i,:) = qDesired(h,:);
    
    % Log Velocity joint data
    Qdot(i,:) = qdot';
    N_QdotDesired(i,:) = qdotDesired(h,:);
    
    % Log Acceleration joint data
    % No lo podemos calcular
    
    % Log Tau IDeal
    tau_ID(i,:) = tau1;
    
    % Log Tau real
    tau_real(i,:) = qtorque;
    
    
    torques_commanded(i,:)=tau;
    torques_read(i,:)=qtorque;
    t_measured(i) = tiempo_actual-t_measured_init;
    send(jointTorquePub,jtMsg);    
end

%% Representación de torques enviados a ejecutar y torques medidos por robot
for i=1:7
    figure;hold on;
    plot(t_measured,torques_commanded(:,i));
    plot(t_measured,tau_ID(:,i));
    plot(t_measured,tau_real(:,i));
    legend('commanded', 'ideal','read');
end

% save('Trayectoria1_Real.mat','Q','torques_commanded','torques_read')


%% Calcular la aceleracion
%
% acceleration = (dV)/(dt) = (V_final - V_inicial)/(t_final - t_inicial)
%
% Comprobamos si la derivada de la posicion 

% Miramos si las posiciones calculadas son correctas
for i=1:7
    figure;hold on;
    plot(t_measured,Q(:,i));
    plot(tt,qDesired(:,i));
    legend('Position Measured(radians)','Position Ideal calculated(radians)');
end

% CALCULAMOS VELOCIDAD a partir de la posicion y tiempo
for i=1:size(Q,1)-1
    q_calculated(i,:) = (Q(i+1,:)-Q(i,:))/(t_measured(i+1)-t_measured(i));
end

% q_corregida = q_calculated;
% q_corregida(8,:) = (N_Q(8+1,:)-N_Q(8,:))/((t_measured(8+1)-t_measured(8))+0.001);
% q_corregida(10,:) = (N_Q(10+1,:)-N_Q(10,:))/((t_measured(10+1)-t_measured(10))-0.001);

% REPRESENTAR VELOCIDAD medida y calculada
for i=1:7
    figure;hold on;
    plot(t_measured,Qdot(:,i),'b');
    plot(t_measured(2:end),q_calculated(:,i),'r');
    legend('Velocity Measured', 'Velocity calculated');
end

% CALCULAMOS ACELERACION a partir de VELOCIDAD y TIEMPO 

for i=1:size(N_Q,1)-1
    qddot_calculated(i,:) = (N_Qdot(i+1,:)-N_Qdot(i,:))/(t_measured(i+1)-t_measured(i));
end

% REPRESENTAR ACELERACION calculada
for i=1:7
    figure;hold on;
    plot(t_measured(2:end),qddot_calculated(:,i),'r');
    legend('Acceleration calculated');
end

% save('Input-Dataset-Trayectory9.mat','t_measured','Q','Qdot','tau_ID','tau_real')

%% Pruebas Narpa

% FALLO: Reducir Fuerza aplicada a la mitad para ver si se reduce el desfase en
% ejes pares
tauFeedForward_m = tauFeedForward/2

for i=1:7
    figure;hold on;
    plot(tauFeedForward(:,i));
    plot(tauFeedForward_m(:,i));
    legend('commanded', 'read');
end

% FALLO: Comprobar que la trayectoria realizada es la deseada
% Resultado: La trayectoria se realiza de forma correcta

for i=1:7
    figure;hold on;
    plot(tt,qDesired(:,i));
    plot(t_measured,Q(:,i));
    legend('Desired', 'ejecuted');
end

for i=1:7
    figure;hold on;
    plot(t_measured,torques_commanded(:,i));
    plot(t_measured,torques_read(:,i));
    legend('commanded', 'read');
end

%% Medir componentes X,Y,Z de cada articulación
% -Joint3.Torque.X = -Joint4.Torque.y

for i=2:2:6
    figure;hold on;
    plot(t_measured,torques_commanded(:,i));
    plot(t_measured,torques_read(:,i));
    legend('commanded', 'read');
end

for i=1:9
    figure;hold on;
    plot(t_measured,torques_commanded(:,6));
    plot(t_measured,torques_read(:,i));
    legend('commanded', 'read');
end

% Mantener un valor de fuerza en el tiempo

